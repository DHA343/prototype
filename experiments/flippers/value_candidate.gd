extends PinballMotion

const Refined = preload("res://experiments/flippers/refined_motion.gd")

var refined: bool = false
var native_response: Callable
var _plans: Array[PinballFlipper.Swing] = []
var _initial: Dictionary = {}
var _elapsed: float = 0.0
var _duration: float = 0.0


func _init(target: CharacterBody2D) -> void:
	super(target)
	native_contact = _native_response


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_plans = Refined.plans_for(swings, 4) if refined else swings
	_elapsed = 0.0
	_duration = delta
	_initial.clear()
	if not flippers.is_target_disabled(body.get_instance_id()) or step_velocity(body.velocity, delta).y > 1:
		for plan: PinballFlipper.Swing in _plans:
			_initial[plan.flipper.get_instance_id()] = not plan.flipper._contact_at(
				body.global_position, radius, _pose(plan.flipper, 0), 0, 0).is_empty()
	super.advance(delta, _plans)


func apply_swept_contact(hit: Dictionary) -> void:
	super.apply_swept_contact(hit)
	_elapsed += hit.time


func contact_separation(hit: Dictionary) -> Vector2:
	var item: PinballFlipper = hit.flipper
	if not _initial[item.get_instance_id()] and item._contact_at(
			body.global_position, radius, _pose(item, _elapsed), 0, 0).is_empty():
		return hit.normal * (maxf(0.0, hit.depth) + SEPARATION_MARGIN)
	return super.contact_separation(hit)


func _native_response(collision: KinematicCollision2D) -> void:
	if not _initial.is_empty():
		var motion := body.velocity * maxf(0.0, _duration - _elapsed)
		var fraction := 0.0
		if motion.length_squared() > 0.000001:
			fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
		_elapsed += (_duration - _elapsed) * fraction
	native_response.call(collision)


func _pose(item: PinballFlipper, time: float) -> Transform2D:
	for plan: PinballFlipper.Swing in _plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
	return item.global_transform
