@tool
class_name TableFlipper
extends PinballFlipper

@export_range(0.0, 240.0, 12.0, "suffix:px") var extra_thickness: float = 48.0:
	set(value):
		extra_thickness = value
		if is_node_ready():
			_reset_bounds()
			_update_shape()

var fixed_left: float = 0.0
var fixed_right: float = 0.0
var fixed_bottom: float = 0.0
var _cached_pose: Transform2D = Transform2D.IDENTITY
var _cached_polygon: PackedVector2Array = PackedVector2Array()
var _applied_pose: Transform2D = Transform2D.IDENTITY
var _shape_dirty: bool = true


func configure(start: Vector2, end: Vector2, hand: int) -> void:
	super.configure(start, end, hand)
	_reset_bounds()
	_update_shape()


func polygon_at(pose: Transform2D) -> PackedVector2Array:
	if not _cached_polygon.is_empty() and pose == _cached_pose:
		return _cached_polygon
	var points := world_polygon_at(pose)
	var inverse := pose.affine_inverse()
	for index in points.size():
		points[index] = inverse * points[index]
	_cached_pose = pose
	_cached_polygon = points
	return _cached_polygon


func world_polygon_at(pose: Transform2D) -> PackedVector2Array:
	var root := pose * Vector2(0.0, _direction * _root_radius)
	var tip := pose * _tip.position
	var slope := (tip.y - root.y) / (tip.x - root.x)
	return PackedVector2Array([
		Vector2(fixed_left, root.y + (fixed_left - root.x) * slope),
		Vector2(fixed_right, root.y + (fixed_right - root.x) * slope),
		Vector2(fixed_right, fixed_bottom), Vector2(fixed_left, fixed_bottom),
	])


func upward_separation(center: Vector2, radius: float, pose: Transform2D, margin: float = 0.15) -> float:
	if _contact_at(center, radius, pose, 0.0, 0.0).is_empty():
		return margin
	var points := world_polygon_at(pose)
	var top := minf(points[0].y, points[1].y)
	var low := 0.0
	var high := maxf(0.0, center.y + radius - top) + margin
	for iteration in 16:
		var middle := (low + high) * 0.5
		if _contact_at(center + Vector2.UP * middle, radius, pose, 0.0, 0.0).is_empty():
			high = middle
		else:
			low = middle
	return high + margin


func advance(
	delta: float, pressed: bool, swing_angle: float, raise_speed: float, return_speed: float,
) -> void:
	super.advance(delta, pressed, swing_angle, raise_speed, return_speed)
	_update_shape()


func reset_motion() -> void:
	super.reset_motion()
	_update_shape()


func plan_motion(pressed: bool, swing_angle: float, speed: float) -> Swing:
	var swing := super.plan_motion(pressed, swing_angle, speed)
	if swing != null:
		var x_reach := maxf(absf(fixed_left - swing.origin.x), absf(fixed_right - swing.origin.x))
		var y_reach := maxf(swing.reach, absf(fixed_bottom - swing.origin.y))
		swing.reach = maxf(swing.reach, Vector2(x_reach, y_reach).length())
	return swing


func surface_velocity_at(point: Vector2, equalization: float = 0.0) -> Vector2:
	var pose := global_transform
	return _surface_velocity_for_contact(point, pose, angular_velocity, equalization,
		_is_upper_contact(point, pose))


func _contact_outline(pose: Transform2D) -> PackedVector2Array:
	return polygon_at(pose)


func _is_shot_face(point: Vector2, _normal: Vector2, pose: Transform2D) -> bool:
	return _is_upper_contact(point, pose)


func _surface_velocity_for_contact(
	point: Vector2, pose: Transform2D, omega: float, equalization: float, on_shot_face: bool,
) -> Vector2:
	if not on_shot_face:
		return Vector2.ZERO
	var rotation_velocity := super._surface_velocity_for_contact(
		point, pose, omega, equalization, on_shot_face)
	return _upper_velocity(rotation_velocity, pose)


func _is_upper_contact(point: Vector2, pose: Transform2D) -> bool:
	var points := world_polygon_at(pose)
	var nearest := Geometry2D.get_closest_point_to_segment(point, points[0], points[1])
	return nearest.distance_squared_to(point) < 0.000004


func _upper_velocity(rotating_velocity: Vector2, pose: Transform2D) -> Vector2:
	# X is fixed. Preserve the moving top's normal speed while expressing its vertical motion.
	var normal := pose.basis_xform(Vector2(0.0, _direction)).normalized()
	return Vector2(0.0, rotating_velocity.dot(normal) / normal.y)


func _reset_bounds() -> void:
	var rest := (get_parent() as Node2D).global_transform * Transform2D(_rest_rotation, position)
	var root := rest * Vector2(0.0, _direction * _root_radius)
	var tip := rest * _tip.position
	fixed_left = minf(root.x, tip.x)
	fixed_right = maxf(root.x, tip.x)
	fixed_bottom = -INF
	for point: Vector2 in _outline:
		fixed_bottom = maxf(fixed_bottom, (rest * point).y)
	fixed_bottom += extra_thickness
	_cached_polygon.clear()
	_shape_dirty = true


func _update_shape() -> void:
	if not _shape_dirty and _applied_pose == global_transform:
		return
	_shape.points = polygon_at(global_transform)
	_applied_pose = global_transform
	_shape_dirty = false
	queue_redraw()


func separation_for(center: Vector2, radius: float, hit: Dictionary, margin: float) -> Vector2:
	return Vector2.UP * upward_separation(center, radius, hit.pose, margin)
