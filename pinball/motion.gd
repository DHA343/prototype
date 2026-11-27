@tool
class_name PinballMotion
extends RefCounted

const MAX_CONTACTS: int = 8
const CONTACT_MARGIN: float = 0.03
const SEPARATION_MARGIN: float = 0.15

var body: CharacterBody2D
var radius: float = 15.0
var gravity: float = 2100.0
var max_speed: float = 1950.0
var boundary: PinballBoundary
var flippers: PinballFlippers
var native_contact: Callable
var contact_recorded: Callable
var segment_traveled: Callable
var trajectory_changed: Callable
var segment_start_time: float = 0.0
var elapsed_in_step: float = 0.0
## Historical experiment fixtures can supply their own separation policy.
var separate_new_contacts: bool = true
var _guard_exceptions: Array[PinballFlipper] = []


func _init(target: CharacterBody2D) -> void:
	body = target


static func reflected_velocity(
	incoming: Vector2, normal: Vector2, restitution: float, surface_velocity: Vector2,
) -> Vector2:
	var speed := -(incoming - surface_velocity).dot(normal)
	return incoming + normal * maxf(0.0, speed) * (1.0 + restitution)


static func flipper_approach_speed(incoming: Vector2, hit: Dictionary) -> float:
	return -(incoming - (hit.surface_velocity as Vector2)).dot(hit.normal)


static func is_flip_shot(hit: Dictionary, approach_speed: float) -> bool:
	return hit.is_striking and approach_speed > 0.0


func reset() -> void:
	if flippers != null:
		flippers.release_target(body.get_instance_id())


func step_velocity(current: Vector2, delta: float) -> Vector2:
	return (current + Vector2.DOWN * gravity * delta).limit_length(max_speed)


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	flippers.refresh_target(body, step_velocity(body.velocity, delta).y)
	if flippers.is_target_disabled(body.get_instance_id()):
		_exclude_flippers()
	var active: Array[PinballFlipper.Swing] = []
	var existing := body.get_collision_exceptions()
	for swing: PinballFlipper.Swing in swings:
		if swing.flipper not in existing:
			body.add_collision_exception_with(swing.flipper)
			active.append(swing)
	advance_motion(delta, active)
	for swing: PinballFlipper.Swing in active:
		body.remove_collision_exception_with(swing.flipper)
	for item: PinballFlipper in _guard_exceptions:
		body.remove_collision_exception_with(item)
	_guard_exceptions.clear()


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	body.velocity = step_velocity(body.velocity, delta)
	var remaining := delta
	var swept := not swings.is_empty()
	var update_start := body.global_position
	for _index in MAX_CONTACTS:
		var segment_start := body.global_position
		var motion := body.velocity * remaining
		var collision := body.move_and_collide(motion, swept, CONTACT_MARGIN, true)
		var fraction := 1.0
		if collision != null:
			fraction = 0.0
			if motion.length_squared() > 0.000001:
				fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
		var collision_time := remaining * fraction
		var hit := {}
		var elapsed := delta - remaining
		if swept and not flippers.is_target_disabled(body.get_instance_id()):
			hit = flippers.first_contact(swings, body.global_position, body.velocity,
				radius, elapsed, collision_time)
		var flipper_first: bool = not hit.is_empty() and (collision == null or hit.time < collision_time)
		segment_start_time = elapsed
		var travel_time: float = hit.time if flipper_first else collision_time
		elapsed_in_step = elapsed + travel_time
		if segment_traveled.is_valid():
			var travel: Vector2 = body.velocity * hit.time if flipper_first else motion * fraction
			segment_traveled.call(segment_start, segment_start + travel)
		if flipper_first:
			if separate_new_contacts and _is_new_contact(hit, update_start, elapsed):
				hit.normal_separation = true
			apply_swept_contact(hit)
			remaining -= hit.time
		else:
			if swept:
				body.global_position += motion if collision == null else collision.get_travel()
				body.force_update_transform()
			if collision == null:
				break
			remaining -= collision_time
			if native_contact.is_valid():
				native_contact.call(collision)
			else:
				resolve_contact(collision)
		body.velocity = body.velocity.limit_length(max_speed)
		if remaining < 0.000001:
			break


func apply_swept_contact(hit: Dictionary) -> void:
	var offset := contact_separation(hit)
	body.global_position += body.velocity * hit.time + offset
	body.force_update_transform()
	_respond_to_flipper(hit)


func contact_separation(hit: Dictionary) -> Vector2:
	if hit.get("normal_separation", false):
		return (hit.normal as Vector2) * (maxf(hit.depth, 0.0) + SEPARATION_MARGIN)
	var item: PinballFlipper = hit.flipper
	return item.separation_for(body.global_position + body.velocity * hit.time,
		radius, hit, SEPARATION_MARGIN)


func resolve_contact(collision: KinematicCollision2D) -> void:
	var item := collision.get_collider() as PinballFlipper
	var normal := collision.get_normal()
	var point := collision.get_position()
	if item != null:
		_respond_to_flipper(item.contact_info(point, normal, flippers.power_equalization))
		return
	var moving := collision.get_collider() as CharacterBody2D
	var surface := moving.velocity if moving != null else Vector2.ZERO
	var incoming := -(body.velocity - surface).dot(normal)
	var restitution := boundary.restitution_for(collision.get_collider()) if boundary != null else 0.1
	var bumper := collision.get_collider() as PinballBumper
	var incoming_velocity := body.velocity
	if bumper != null and incoming > 0.0:
		var outward_speed := maxf(incoming * restitution, bumper.exit_speed)
		body.velocity += normal * (incoming + outward_speed)
		if incoming > 30.0:
			bumper.hit(point, body)
	else:
		body.velocity = reflected_velocity(body.velocity, normal, restitution, surface)
	record_trajectory_change(incoming_velocity)
	if incoming > 30:
		_record(point, normal)


func record_trajectory_change(incoming_velocity: Vector2, is_flip: bool = false) -> void:
	if not trajectory_changed.is_valid():
		return
	if is_flip or not body.velocity.is_equal_approx(incoming_velocity):
		trajectory_changed.call(is_flip, elapsed_in_step)


func _is_new_contact(hit: Dictionary, update_start: Vector2, elapsed: float) -> bool:
	# A sweep hit at time zero already proves contact at the start of this interval.
	if hit.time == 0.0:
		return false
	var swing: PinballFlipper.Swing = hit.swing
	var item := swing.flipper
	if not item._contact_at(update_start, radius, swing.pose_at(0.0), 0.0, 0.0).is_empty():
		return false
	var interval_start := body.global_position
	# Recovery can change the next interval's start without consuming movement time.
	return (elapsed == 0.0 and interval_start == update_start) or item._contact_at(
		interval_start, radius, swing.pose_at(elapsed), 0.0, 0.0).is_empty()


func _respond_to_flipper(hit: Dictionary) -> void:
	var approach_speed := flipper_approach_speed(body.velocity, hit)
	if approach_speed <= 0.0:
		return
	var incoming_velocity := body.velocity
	var is_flip := is_flip_shot(hit, approach_speed)
	if is_flip:
		body.velocity = flippers.shot_velocity(body.velocity, hit, flippers.outward_shot_direction(hit))
		if flippers.disable_target(body):
			_exclude_flippers()
	else:
		body.velocity = reflected_velocity(
			body.velocity, hit.normal, flippers.restitution, hit.surface_velocity)
	record_trajectory_change(incoming_velocity, is_flip)
	if approach_speed > 30:
		_record(hit.point, hit.normal)


func _exclude_flippers() -> void:
	for item: PinballFlipper in flippers.items:
		if item not in body.get_collision_exceptions():
			body.add_collision_exception_with(item)
			_guard_exceptions.append(item)


func _record(point: Vector2, normal: Vector2) -> void:
	if contact_recorded.is_valid():
		contact_recorded.call(point, normal)
