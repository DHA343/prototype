extends "res://experiments/flippers/tests/native_motion.gd"

const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")
const QuadMotion = preload("res://experiments/flippers/quad_motion.gd")
const Shot = preload("res://experiments/flippers/shot_flipper.gd")

var detector: String = "B"
var normal_for_new_contact: bool = false
var split_budgets: bool = false
var guard_released: bool = false
var cap_reason: String = ""
var movement_contacts: int = 0
var recovery_contacts: int = 0
var _plans: Array[PinballFlipper.Swing] = []
var _initial_overlaps: Dictionary = {}
var _context: Dictionary = {}
var _before_time: float = 0.0
var _budget_discard: float = 0.0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_plans = swings
	if detector == "B+4":
		_plans = RefinedMotion.plans_for(swings, 4)
	elif detector == "D2":
		_plans = QuadMotion.plans_for(swings)
	guard_released = flippers.is_target_disabled(body.get_instance_id()) and step_velocity(body.velocity, delta).y > 1.0
	_initial_overlaps.clear()
	for item: PinballFlipper in flippers.items:
		var hit := item._contact_at(body.global_position, radius, _pose_at(item, 0.0), 0.0, 0.0)
		_initial_overlaps[item.get_instance_id()] = not hit.is_empty()
	cap_reason = ""
	movement_contacts = 0
	recovery_contacts = 0
	_budget_discard = 0.0
	super.advance(delta, _plans)
	if split_budgets:
		discarded_seconds = _budget_discard
	elif discarded_seconds > 0.0:
		cap_reason = "shared_8"
	for event: Dictionary in events:
		if not split_budgets:
			if event.velocity_delta_px_s > 0.01:
				movement_contacts += 1
			else:
				recovery_contacts += 1


func apply_swept_contact(hit: Dictionary) -> void:
	_before_time = _elapsed
	var item: PinballFlipper = hit.flipper
	if detector == "D2" and item is Shot:
		# D2's geometry helper otherwise supplies its own legacy shot flags.
		for plan: PinballFlipper.Swing in _plans:
			if plan.flipper == item:
				var omega := plan.speed if _elapsed + float(hit.time) < plan.stop_time else 0.0
				hit = (item as Shot).shot_contact(hit, omega, flippers.power_equalization)
				break
	var initial: bool = _initial_overlaps[item.get_instance_id()]
	var overlap := item._contact_at(body.global_position, radius, _pose_at(item, _elapsed), 0.0, 0.0)
	_context = {"tick_initial_overlap": initial, "query_start_overlap": not overlap.is_empty(),
		"query_start_depth_px": overlap.get("depth", 0.0), "guard_released": guard_released,
		"depth_px": hit.depth, "surface_velocity": _vec(hit.surface_velocity),
		"faces": _faces(item, hit.point, hit.pose),
		"relative_normal_before": (body.velocity - (hit.surface_velocity as Vector2)).dot(hit.normal),
		"separation_policy": "upward", "query_time_ms": hit.time * 1000.0}
	_context["category"] = "release_overlap" if guard_released and initial else (
		"tick_overlap" if initial else ("recontact_overlap" if not overlap.is_empty() else "new_contact"))
	super.apply_swept_contact(hit)


func contact_separation(hit: Dictionary) -> Vector2:
	var offset: Vector2
	if normal_for_new_contact and not _context.query_start_overlap and not _context.tick_initial_overlap:
		_context.separation_policy = "normal_new_contact"
		offset = (hit.normal as Vector2) * (maxf(0.0, hit.depth) + SEPARATION_MARGIN)
		_correction = offset
	else:
		offset = super.contact_separation(hit)
	var point: Vector2 = body.global_position + body.velocity * float(hit.time) + offset
	var after: Dictionary = hit.flipper._contact_at(point, radius, hit.pose, 0.0, 0.0)
	_context["post_separation_overlap"] = not after.is_empty()
	_context["post_separation_depth_px"] = after.get("depth", 0.0)
	_context["normal_exit_estimate_px"] = maxf(0.0, hit.depth) + SEPARATION_MARGIN
	return offset


func _native_contact(collision: KinematicCollision2D) -> void:
	_before_time = _elapsed
	var item := collision.get_collider() as PinballFlipper
	var initial: bool = item != null and _initial_overlaps.get(item.get_instance_id(), false)
	var moving := collision.get_collider() as CharacterBody2D
	var surface := item.surface_velocity_at(collision.get_position()) if item != null else (
		moving.velocity if moving != null else Vector2.ZERO)
	_context = {"category": "release_overlap" if guard_released and initial else (
		"tick_overlap" if initial else "native_contact"), "guard_released": guard_released,
		"tick_initial_overlap": initial,
		"depth_px": collision.call("get_depth") if collision.has_method("get_depth") else null,
		"faces": _faces(item, collision.get_position(), item.global_transform) if item != null else [],
		"surface_velocity": _vec(surface),
		"separation_policy": "Godot"}
	super._native_contact(collision)


func _record_event(hit: Dictionary, incoming: Vector2, shot: bool) -> void:
	super._record_event(hit, incoming, shot)
	var event: Dictionary = events.back()
	event.merge(_context, true)
	if not event.has("surface_velocity"):
		event["surface_velocity"] = _vec(hit.get("surface_velocity", Vector2.ZERO))
	event["incoming_velocity"] = _vec(incoming)
	event["velocity_delta_px_s"] = incoming.distance_to(body.velocity.limit_length(max_speed))
	if not event.has("relative_normal_before"):
		event["relative_normal_before"] = (incoming - Vector2(event.surface_velocity[0], event.surface_velocity[1])).dot(hit.normal)
	event["relative_normal_after"] = (body.velocity.limit_length(max_speed) - Vector2(event.surface_velocity[0], event.surface_velocity[1])).dot(hit.normal)
	event["separation_vector"] = _vec(_correction)
	event["remaining_before_ms"] = maxf(0.0, _duration - _before_time) * 1000.0
	event["remaining_after_ms"] = maxf(0.0, _duration - _elapsed) * 1000.0
	event["disabled_after"] = flippers.is_target_disabled(body.get_instance_id())


func _pose_at(item: PinballFlipper, at: float) -> Transform2D:
	for plan: PinballFlipper.Swing in _plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(at, plan.stop_time), item.position)
	return item.global_transform


func _faces(item: PinballFlipper, point: Vector2, pose: Transform2D) -> Array[String]:
	var table := item as TableFlipper
	var result: Array[String] = []
	if table != null:
		var polygon := table.world_polygon_at(pose)
		for index in 4:
			var nearest := Geometry2D.get_closest_point_to_segment(point, polygon[index], polygon[(index + 1) % 4])
			if nearest.distance_squared_to(point) < 0.000004:
				result.append(["top", "right", "bottom", "left"][index])
	return result


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	if not split_budgets:
		super.advance_motion(delta, swings)
		return
	# Experimental factor: only the budget accounting differs from production.
	body.velocity = step_velocity(body.velocity, delta)
	var remaining := delta
	var swept := not swings.is_empty()
	for index in MAX_CONTACTS * 2:
		var incoming := body.velocity
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
			apply_swept_contact(hit)
			remaining -= hit.time
		else:
			if swept:
				body.global_position += motion if collision == null else collision.get_travel()
				body.force_update_transform()
			if collision == null:
				return
			remaining -= collision_time
			if native_contact.is_valid():
				native_contact.call(collision)
			else:
				resolve_contact(collision)
		body.velocity = body.velocity.limit_length(max_speed)
		if incoming.distance_to(body.velocity) > 0.01:
			movement_contacts += 1
		else:
			recovery_contacts += 1
		if remaining < 0.000001:
			return
		if movement_contacts >= MAX_CONTACTS or recovery_contacts >= MAX_CONTACTS:
			_budget_discard = remaining
			cap_reason = "velocity_8" if movement_contacts >= MAX_CONTACTS else "recovery_8"
			return
