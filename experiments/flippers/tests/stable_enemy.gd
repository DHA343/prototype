extends "res://experiments/flippers/tests/causal_enemy.gd"


func advance(delta: float) -> void:
	if not trace_enabled:
		super.advance(delta)
		return
	trace = {}
	if not active:
		return
	var before := global_position
	var motion := (_movement_velocity + knockback_velocity()) * delta + crowd_motion
	trace = {"before": _vec(before), "requested_motion": _vec(motion),
		"crowd_motion": _vec(crowd_motion), "contacts": [], "stopped_by_budget": false,
		"segments": [], "raw_matches": true}
	var elapsed := 0.0
	for index: int in MAX_CONTACTS:
		var remaining := maxf(0.0, delta - elapsed)
		var parameters := PhysicsTestMotionParameters2D.new()
		parameters.from = global_transform
		parameters.motion = motion
		parameters.margin = 0.03
		parameters.recovery_as_collision = true
		var raw := PhysicsTestMotionResult2D.new()
		var collision := move_and_collide(motion, false, 0.03, true)
		var fraction := 1.0
		if collision != null:
			var found := PhysicsServer2D.body_test_motion(get_rid(), parameters, raw)
			fraction = raw.get_collision_safe_fraction()
			trace.raw_matches = trace.raw_matches and found and raw.get_collider_rid() == collision.get_collider_rid()
		var duration := remaining * fraction
		trace.segments.append({"start_time": elapsed, "duration": duration,
			"start": _vec(global_position - motion * fraction),
			"velocity": _vec(motion / remaining if remaining > 0.0 else Vector2.ZERO)})
		elapsed += duration
		if collision == null:
			break
		var normal := collision.get_normal()
		motion = collision.get_remainder().slide(normal)
		if _movement_velocity.dot(normal) < 0.0:
			_movement_velocity = _movement_velocity.slide(normal)
		if _knockback_initial.dot(normal) < 0.0:
			_knockback_initial = _knockback_initial.slide(normal)
		trace.contacts.append({"target": str(collision.get_collider().name), "normal": _vec(normal),
			"depth_px": collision.get_depth(), "travel": _vec(collision.get_travel()),
			"remaining_motion": _vec(motion), "position": _vec(global_position)})
		if motion.length_squared() < 0.000001:
			break
		trace.stopped_by_budget = index == MAX_CONTACTS - 1
	trace.segments.append({"start_time": elapsed, "duration": maxf(0.0, delta - elapsed),
		"start": _vec(global_position), "velocity": [0.0, 0.0]})
	velocity = (global_position - before) / delta
	_knockback_elapsed += delta
	if _knockback_elapsed >= knockback_duration:
		_knockback_initial = Vector2.ZERO
	crowd_motion = Vector2.ZERO
	trace["after"] = _vec(global_position)
	trace["velocity"] = _vec(velocity)
	trace["residual_motion_px"] = motion.length() if trace.stopped_by_budget else 0.0
