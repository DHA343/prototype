@tool
class_name PinballFlipper
extends StaticBody2D

const COLOR: Color = Color(0.45, 0.72, 0.8)
const PIVOT_COLOR: Color = Color(0.08, 0.14, 0.18)
const ROUND_STEPS: int = 32
const SWEEP_STEP: float = 4.0

@export var pivot_socket: PinballSocket:
	set(value):
		if pivot_socket != null and pivot_socket.changed.is_connected(_schedule_fit):
			pivot_socket.changed.disconnect(_schedule_fit)
		pivot_socket = value
		if pivot_socket != null and not pivot_socket.changed.is_connected(_schedule_fit):
			pivot_socket.changed.connect(_schedule_fit)
		_schedule_fit()
@export var tip_socket: PinballSocket:
	set(value):
		if tip_socket != null and tip_socket.changed.is_connected(_schedule_fit):
			tip_socket.changed.disconnect(_schedule_fit)
		tip_socket = value
		if tip_socket != null and not tip_socket.changed.is_connected(_schedule_fit):
			tip_socket.changed.connect(_schedule_fit)
		_schedule_fit()
@export_enum("Left", "Right") var side: int = 0

var length: float = 3.0
var angular_velocity: float = 0.0
var root_width: float = 36.0
var tip_width: float = 18.0
var _rest_rotation: float = 0.0
var _offset: float = 0.0
var _direction: float = -1.0
var _fit_pending: bool = false
var _parent_transform: Transform2D = Transform2D.IDENTITY
var _outline: PackedVector2Array = PackedVector2Array()
var _root_radius: float = 18.0
var _sweep_reach: float = 0.0

@onready var _collision: CollisionShape2D = $CollisionShape2D
@onready var _pivot: Marker2D = $Pivot
@onready var _tip: Marker2D = $Tip
@onready var _shape: ConvexPolygonShape2D = _collision.shape.duplicate() as ConvexPolygonShape2D


static func _point_velocity(
	arm: Vector2, tip_arm: Vector2, omega: float, equalization: float,
) -> Vector2:
	var effective_arm := arm.lerp(tip_arm, equalization)
	return Vector2(-effective_arm.y, effective_arm.x) * omega


func _ready() -> void:
	_collision.shape = _shape
	set_notify_transform(true)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready():
		var parent := get_parent() as Node2D
		if parent != null and parent.global_transform != _parent_transform:
			_schedule_fit()


func _draw() -> void:
	if _outline.is_empty():
		return
	draw_colored_polygon(_outline, COLOR)
	draw_circle(Vector2.ZERO, 4.5, PIVOT_COLOR)


func set_widths(root: float, tip: float) -> void:
	root_width = root
	tip_width = tip
	if is_node_ready():
		_fit()


func configure(start: Vector2, end: Vector2, hand: int) -> void:
	length = start.distance_to(end)
	side = hand
	_rest_rotation = (end - start).angle()
	_direction = -1.0 if side == 0 else 1.0
	_root_radius = root_width * 0.5
	var tip_radius := minf(tip_width, root_width) * 0.5
	var inward := -_direction
	# Sockets remain on the contact surface; the pivot is at the root's center.
	position = start + Vector2(0.0, inward * _root_radius).rotated(_rest_rotation)
	_pivot.position = Vector2.ZERO
	_tip.position = Vector2(length, -inward * _root_radius)
	var tip_center := Vector2(length, inward * (tip_radius - _root_radius))
	var samples := PackedVector2Array()
	for index in ROUND_STEPS:
		var radial := Vector2.RIGHT.rotated(TAU * index / ROUND_STEPS)
		samples.append(radial * _root_radius)
		samples.append(tip_center + radial * tip_radius)
	_outline = Geometry2D.convex_hull(samples)
	# convex_hull closes the polygon; the physics shape takes unique vertices.
	_outline.resize(_outline.size() - 1)
	_sweep_reach = maxf(_root_radius, tip_center.length() + tip_radius)
	_shape.points = _outline
	rotation = _rest_rotation + _offset
	force_update_transform()
	queue_redraw()


func advance(
	delta: float, pressed: bool, swing_angle: float, raise_speed: float, return_speed: float,
) -> void:
	var target := _target_offset(pressed, swing_angle)
	var speed := deg_to_rad(raise_speed if pressed else return_speed)
	var previous := _offset
	_offset = move_toward(_offset, target, speed * delta)
	angular_velocity = (_offset - previous) / delta
	rotation = _rest_rotation + _offset
	force_update_transform()


func reset_motion() -> void:
	_offset = 0.0
	angular_velocity = 0.0
	rotation = _rest_rotation
	force_update_transform()
	reset_physics_interpolation()


func step_limit(ball_radius: float, pressed: bool, swing_angle: float, speed: float) -> float:
	var target := _target_offset(pressed, swing_angle)
	if is_equal_approx(_offset, target):
		return INF
	# Moving the tip by at most half a ball radius prevents a rotating surface skipping it.
	var reach := _tip.position.length() + tip_width * 0.5
	return maxf(ball_radius * 0.5, 0.75) / maxf(reach * deg_to_rad(speed), 0.001)


func surface_velocity_at(point: Vector2, equalization: float = 0.0) -> Vector2:
	return _point_velocity(point - global_position, tip_position() - global_position,
		angular_velocity, equalization)


func is_rising() -> bool:
	return angular_velocity * _direction > 0.0


func is_striking(point: Vector2, normal: Vector2) -> bool:
	# The round root joins a fixed wall; touching it must not grant a powered shot.
	return is_rising() and to_local(point).x > 0.0 and normal.dot(strike_normal()) > 0.5


func strike_normal() -> Vector2:
	return global_transform.basis_xform(Vector2(0.0, _direction)).normalized()


func root_surface_position() -> Vector2:
	return to_global(Vector2(0.0, _direction * _root_radius))


func contact_ratio(point: Vector2) -> float:
	return clampf(to_local(point).x / length, 0.0, 1.0)


func tip_position() -> Vector2:
	return _tip.global_position


func is_near_shot_face(center: Vector2, reach: float) -> bool:
	var contact := _contact_at(center, reach, global_transform, 0.0, 0.0)
	return contact.get("on_shot_face", false)


func swing_top(swing_angle: float) -> float:
	var parent_pose := (get_parent() as Node2D).global_transform
	var vertical := Vector2(parent_pose.x.y, parent_pose.y.y)
	var turn := _target_offset(true, swing_angle)
	var top := INF
	for point: Vector2 in _outline:
		var start := point.rotated(_rest_rotation)
		var height := minf(start.dot(vertical), start.rotated(turn).dot(vertical))
		var peak := angle_difference(start.angle(), vertical.angle() + PI)
		if peak * turn >= 0.0 and absf(peak) <= absf(turn):
			height = -start.length() * vertical.length()
		top = minf(top, height)
	return global_position.y + top


func plan_motion(pressed: bool, swing_angle: float, speed: float) -> Swing:
	var target := _target_offset(pressed, swing_angle)
	var difference := target - _offset
	if is_zero_approx(difference):
		return null

	var swing := Swing.new()
	swing.flipper = self
	swing.start_angle = _rest_rotation + _offset
	swing.speed = signf(difference) * deg_to_rad(speed)
	swing.stop_time = absf(difference / swing.speed)
	swing.parent_pose = (get_parent() as Node2D).global_transform
	swing.origin = global_position
	var basis := swing.parent_pose
	var basis_scale := maxf(basis.x.length(), basis.y.length())
	if not is_zero_approx(basis.x.dot(basis.y)):
		basis_scale = basis.x.length() + basis.y.length()
	swing.reach = _sweep_reach * basis_scale
	return swing


func predicted_contact(
	center: Vector2, ball_radius: float, elapsed: float, delta: float,
	swing_angle: float, raise_speed: float, equalization: float = 0.0,
) -> Dictionary:
	var target := _target_offset(true, swing_angle)
	var speed := deg_to_rad(raise_speed)
	var offset := move_toward(_offset, target, speed * elapsed)
	var previous := move_toward(_offset, target, speed * maxf(0.0, elapsed - delta))
	var parent_transform := (get_parent() as Node2D).global_transform
	var pose := parent_transform * Transform2D(_rest_rotation + offset, position)
	return _contact_at(center, ball_radius, pose, (offset - previous) / delta, equalization)


func separation_for(_center: Vector2, _radius: float, hit: Dictionary, margin: float) -> Vector2:
	return (hit.normal as Vector2) * (hit.depth + margin)


func _target_offset(pressed: bool, swing_angle: float) -> float:
	return _direction * deg_to_rad(swing_angle) if pressed else 0.0


func _contact_at(
	center: Vector2, ball_radius: float, pose: Transform2D, omega: float, equalization: float,
) -> Dictionary:
	var start := pose.origin
	var end := pose * _tip.position
	var closest := Vector2.ZERO
	var distance_squared := INF
	var face_normal := Vector2.ZERO
	for index in _outline.size():
		var a := pose * _outline[index]
		var b := pose * _outline[(index + 1) % _outline.size()]
		var candidate := Geometry2D.get_closest_point_to_segment(center, a, b)
		var distance := center.distance_squared_to(candidate)
		if distance < distance_squared:
			distance_squared = distance
			closest = candidate
			var edge := b - a
			face_normal = Vector2(edge.y, -edge.x).normalized()
	var inside := Geometry2D.is_point_in_polygon(pose.affine_inverse() * center, _outline)
	if not inside and distance_squared > ball_radius * ball_radius:
		return {}
	var normal := face_normal if inside else (center - closest).normalized()
	if normal == Vector2.ZERO:
		normal = face_normal
	var point := closest
	var arm := point - start
	var contact_x := (pose.affine_inverse() * point).x
	var ratio := clampf(contact_x / length, 0.0, 1.0)
	var upper_normal := pose.basis_xform(Vector2(0.0, _direction)).normalized()
	var on_shot_face := contact_x > 0.0 and normal.dot(upper_normal) > 0.5
	var is_raising := omega * _direction > 0.0 and on_shot_face
	return {
		"point": point, "normal": normal,
		"pose": pose,
		"depth": ball_radius + sqrt(distance_squared) if inside else ball_radius - sqrt(distance_squared),
		"surface_velocity": _point_velocity(arm, end - start, omega, 0.0),
		"strike_surface_velocity": _point_velocity(arm, end - start, omega,
			equalization if is_raising else 0.0),
		"ratio": ratio,
		"on_shot_face": on_shot_face,
		"is_striking": is_raising,
	}


func _schedule_fit() -> void:
	if is_node_ready() and not _fit_pending:
		_fit_pending = true
		_fit.call_deferred()


func _fit() -> void:
	_fit_pending = false
	var valid := pivot_socket != null and tip_socket != null
	if valid:
		valid = pivot_socket.available and tip_socket.available \
			and not pivot_socket.global_position.is_equal_approx(tip_socket.global_position)
	visible = valid
	collision_layer = 2 if valid else 0
	if not valid:
		return
	# Express both wall sockets in the flipper parent's coordinates.
	var parent := get_parent() as Node2D
	_parent_transform = parent.global_transform
	configure(
		parent.to_local(pivot_socket.global_position),
		parent.to_local(tip_socket.global_position),
		side
	)


class Swing:
	var flipper: PinballFlipper
	var start_angle: float
	var speed: float
	var stop_time: float
	var parent_pose: Transform2D
	var origin: Vector2
	var reach: float

	func sweep(
		center: Vector2, velocity: Vector2, radius: float,
		elapsed: float, duration: float, equalization: float, accept: Callable = Callable(),
	) -> Dictionary:
		var end := center + velocity * duration
		var nearest := center
		if not center.is_equal_approx(end):
			nearest = Geometry2D.get_closest_point_to_segment(origin, center, end)
		var span := reach + radius
		if nearest.distance_squared_to(origin) > span * span:
			return {}

		var turning_time := clampf(stop_time - elapsed, 0.0, duration)
		# Include the instant at which the flipper stops moving, even inside a sample.
		if turning_time > 0.0 or (duration == 0.0 and elapsed < stop_time):
			var moving := _sample(
				center, velocity, radius, elapsed, turning_time, speed, equalization, accept,
			)
			if not moving.is_empty() or turning_time >= duration:
				return moving
		var still := _sample(
			center + velocity * turning_time, velocity, radius, elapsed + turning_time,
			duration - turning_time, 0.0, equalization, accept,
		)
		if not still.is_empty():
			still.time += turning_time
		return still

	func _sample(
		center: Vector2, velocity: Vector2, radius: float, elapsed: float,
		duration: float, omega: float, equalization: float, accept: Callable,
	) -> Dictionary:
		var travel := (velocity.length() + absf(omega) * reach) * duration
		var samples := maxi(1, ceili(travel / SWEEP_STEP))
		for index in range(samples + 1 if duration > 0.0 else 1):
			var time := duration * float(index) / samples
			var at := elapsed + time
			var angle := start_angle + speed * minf(at, stop_time)
			var pose := parent_pose * Transform2D(angle, flipper.position)
			var hit := flipper._contact_at(center + velocity * time, radius, pose, omega, equalization)
			if hit.is_empty():
				continue
			if accept.is_valid() and not accept.call(hit):
				continue
			var normal: Vector2 = hit.normal
			var surface: Vector2 = hit.surface_velocity
			if hit.depth > 0.01 or (velocity - surface).dot(normal) < 0.0:
				hit.time = time
				hit.flipper = flipper
				return hit
		return {}
