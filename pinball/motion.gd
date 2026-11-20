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
var struck_flippers: Array[PinballFlipper] = []
var native_contact: Callable
var swept_contact: Callable
var separation: Callable
var contact_recorded: Callable
var _guard_exceptions: Array[PinballFlipper] = []


func _init(target: CharacterBody2D) -> void:
	body = target


static func reflected_velocity(
	incoming: Vector2, normal: Vector2, restitution: float, surface_velocity: Vector2,
) -> Vector2:
	var speed := -(incoming - surface_velocity).dot(normal)
	return incoming + normal * maxf(0.0, speed) * (1.0 + restitution)


func reset() -> void:
	struck_flippers.clear()
	if flippers != null:
		flippers.release_target(body.get_instance_id())


func step_velocity(current: Vector2, delta: float) -> Vector2:
	return (current + Vector2.DOWN * gravity * delta).limit_length(max_speed)


func advance(delta: float, swings: Array[PinballFlipper.Swing] = [], integrate: Callable = Callable()) -> void:
	flippers.refresh_target(body, step_velocity(body.velocity, delta).y)
	if flippers.is_target_disabled(body.get_instance_id()):
		_exclude_flippers()
	var active: Array[PinballFlipper.Swing] = []
	var existing := body.get_collision_exceptions()
	for swing: PinballFlipper.Swing in swings:
		if swing.flipper not in existing:
			body.add_collision_exception_with(swing.flipper)
			active.append(swing)
	for index in range(struck_flippers.size() - 1, -1, -1):
		if not struck_flippers[index].is_rising():
			struck_flippers.remove_at(index)
	if integrate.is_valid():
		integrate.call(delta, active)
	else:
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
	for _index in MAX_CONTACTS:
		var motion := body.velocity * remaining
		var collision := body.move_and_collide(motion, swept, CONTACT_MARGIN, true)
		var fraction := 1.0
		if collision != null:
			fraction = 0.0
			if motion.length_squared() > 0.000001:
				fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
		var collision_time := remaining * fraction
		var hit := {}
		if swept and not flippers.is_target_disabled(body.get_instance_id()):
			hit = flippers.first_contact(swings, body.global_position, body.velocity,
				radius, delta - remaining, collision_time)
		if not hit.is_empty() and (collision == null or hit.time < collision_time):
			if swept_contact.is_valid():
				swept_contact.call(hit)
			else:
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
	var offset: Vector2 = separation.call(hit) if separation.is_valid() else contact_separation(hit)
	body.global_position += body.velocity * hit.time + offset
	body.force_update_transform()
	_respond_to_flipper(hit)


func contact_separation(hit: Dictionary) -> Vector2:
	var item: PinballFlipper = hit.flipper
	return item.separation_for(body.global_position + body.velocity * hit.time,
		radius, hit, SEPARATION_MARGIN)


func resolve_contact(collision: KinematicCollision2D) -> void:
	var item := collision.get_collider() as PinballFlipper
	var normal := collision.get_normal()
	var point := collision.get_position()
	if item != null:
		var striking := item.is_striking(point, normal)
		_respond_to_flipper({"flipper": item, "point": point, "normal": normal,
			"ratio": item.contact_ratio(point), "is_striking": striking,
			"surface_velocity": item.surface_velocity_at(point),
			"strike_surface_velocity": item.surface_velocity_at(point,
				flippers.power_equalization if striking else 0)})
		return
	var moving := collision.get_collider() as CharacterBody2D
	var surface := moving.velocity if moving != null else Vector2.ZERO
	var incoming := -(body.velocity - surface).dot(normal)
	var restitution := boundary.restitution_for(collision.get_collider()) if boundary != null else 0.1
	body.velocity = reflected_velocity(body.velocity, normal, restitution, surface)
	if incoming > 30:
		_record(point, normal)


func _respond_to_flipper(hit: Dictionary) -> void:
	var normal: Vector2 = hit.normal
	var incoming := -(body.velocity - (hit.surface_velocity as Vector2)).dot(normal)
	if incoming <= 0:
		return
	var item: PinballFlipper = hit.flipper
	var already_struck := item in struck_flippers
	if hit.is_striking and already_struck and body.velocity.dot(normal) > 0:
		return
	if hit.is_striking and not already_struck:
		struck_flippers.append(item)
		body.velocity = reflected_velocity(body.velocity, normal, flippers.restitution, hit.strike_surface_velocity)
		body.velocity = flippers.direct_shot(body.velocity, hit.ratio, item.side, normal)
		if flippers.disable_target(body):
			_exclude_flippers()
	else:
		body.velocity = reflected_velocity(body.velocity, normal, flippers.restitution, hit.surface_velocity)
	if incoming > 30:
		_record(hit.point, normal)


func _exclude_flippers() -> void:
	for item: PinballFlipper in flippers.items:
		if item not in body.get_collision_exceptions():
			body.add_collision_exception_with(item)
			_guard_exceptions.append(item)


func _record(point: Vector2, normal: Vector2) -> void:
	if contact_recorded.is_valid():
		contact_recorded.call(point, normal)
