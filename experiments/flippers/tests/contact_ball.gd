extends "res://experiments/flippers/tests/matrix_enemy_probe.gd"

var contact_limit: int = 8
var exhausted_updates: int = 0
var discarded_seconds: float = 0.0
var zero_time_contacts: int = 0
var exhausted_traces: Array[Dictionary] = []
var no_progress_contacts: int = 0


func reset_audit() -> void:
	exhausted_updates = 0
	discarded_seconds = 0
	zero_time_contacts = 0
	exhausted_traces.clear()
	no_progress_contacts = 0


func _advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	# Same traversal as PinballBall. Only the cap and test counters are changed.
	velocity = step_velocity(velocity, delta)
	var remaining := delta
	var swept := not swings.is_empty()
	var trace: Array[Dictionary] = []
	for index in contact_limit:
		var before := velocity
		var before_position := global_position
		var motion := velocity * remaining
		var collision := move_and_collide(motion, swept, CONTACT_MARGIN, true)
		var fraction := 1.0
		if collision != null:
			fraction = 0.0
			if motion.length_squared() > 0.000001:
				fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
		var collision_time := remaining * fraction
		var hit := {}
		if swept:
			hit = flippers.first_contact(swings, global_position, velocity, radius,
				delta - remaining, collision_time)
		if not hit.is_empty() and (collision == null or hit.time < collision_time):
			zero_time_contacts += int(hit.time < 0.000001)
			_apply_swept_contact(hit)
			remaining -= hit.time
			trace.append({"target": str(hit.flipper.name), "time_ms": hit.time * 1000,
				"changed_velocity": before.distance_to(velocity) > 0.01,
				"position_delta_px": before_position.distance_to(global_position)})
		else:
			if swept:
				global_position += motion if collision == null else collision.get_travel()
				force_update_transform()
			if collision == null:
				return
			zero_time_contacts += int(collision_time < 0.000001)
			remaining -= collision_time
			_resolve_contact(collision)
			trace.append({"target": str(collision.get_collider().name), "time_ms": collision_time * 1000,
				"changed_velocity": before.distance_to(velocity) > 0.01,
				"position_delta_px": before_position.distance_to(global_position)})
		var last: Dictionary = trace.back()
		no_progress_contacts += int(last.time_ms < 0.001 and not last.changed_velocity
			and last.position_delta_px < 0.001)
		velocity = velocity.limit_length(max_speed)
		if remaining < 0.000001:
			return
		if index == contact_limit - 1:
			exhausted_updates += 1
			discarded_seconds += remaining
			if exhausted_traces.size() < 4:
				exhausted_traces.append({"remaining_ms": remaining * 1000, "contacts": trace})
