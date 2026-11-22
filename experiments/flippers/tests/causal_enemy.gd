extends Enemy

var trace_enabled: bool = false
var trace: Dictionary = {}


func advance(delta: float) -> void:
	trace = {}
	if not trace_enabled:
		super.advance(delta)
		return
	if not active:
		return
	var before := global_position
	var motion := (_movement_velocity + knockback_velocity()) * delta + crowd_motion
	trace = {"before": _vec(before), "requested_motion": _vec(motion),
		"crowd_motion": _vec(crowd_motion), "contacts": [], "stopped_by_budget": false}
	for index: int in MAX_CONTACTS:
		var collision := move_and_collide(motion, false, 0.03, true)
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
	velocity = (global_position - before) / delta
	_knockback_elapsed += delta
	if _knockback_elapsed >= knockback_duration:
		_knockback_initial = Vector2.ZERO
	crowd_motion = Vector2.ZERO
	trace["after"] = _vec(global_position)
	trace["velocity"] = _vec(velocity)
	trace["residual_motion_px"] = motion.length() if trace.stopped_by_budget else 0.0


static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]
