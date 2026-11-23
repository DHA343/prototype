extends PinballMotion

var native_response: Callable
var _plans: Array[PinballFlipper.Swing] = []
var _initial: Dictionary = {}
var _elapsed: float = 0.0
var _duration: float = 0.0


func _init(target: CharacterBody2D) -> void:
	super(target)
	separate_new_contacts = false
	native_contact = _native_response


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_plans = swings
	_elapsed = 0.0
	_duration = delta
	_initial.clear()
	for item: PinballFlipper in flippers.items:
		_initial[item.get_instance_id()] = not item._contact_at(
			body.global_position, radius, _pose_at(item, 0.0), 0.0, 0.0).is_empty()
	super.advance(delta, swings)


func apply_swept_contact(hit: Dictionary) -> void:
	super.apply_swept_contact(hit)
	_elapsed += float(hit.time)


func contact_separation(hit: Dictionary) -> Vector2:
	var item: PinballFlipper = hit.flipper
	if not _initial[item.get_instance_id()] and item._contact_at(
		body.global_position, radius, _pose_at(item, _elapsed), 0.0, 0.0).is_empty():
		return (hit.normal as Vector2) * (maxf(0.0, hit.depth) + SEPARATION_MARGIN)
	return super.contact_separation(hit)


func _native_response(collision: KinematicCollision2D) -> void:
	var remaining := maxf(0.0, _duration - _elapsed)
	var motion := body.velocity * remaining
	var fraction := 0.0
	if motion.length_squared() > 0.000001:
		fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)
	_elapsed += remaining * fraction
	if native_response.is_valid():
		native_response.call(collision)
	else:
		resolve_contact(collision)


func _pose_at(item: PinballFlipper, time: float) -> Transform2D:
	for plan: PinballFlipper.Swing in _plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
	return item.global_transform
