@tool
extends PinballMotion

# Compatibility for the saved experiments. Production has no method-switching
# callbacks and no per-flipper struck history; guard 3 owns production suppression.
var struck_flippers: Array[PinballFlipper] = []


func reset() -> void:
	struck_flippers.clear()
	super.reset()


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	for index in range(struck_flippers.size() - 1, -1, -1):
		if not struck_flippers[index].is_rising():
			struck_flippers.remove_at(index)
	super.advance(delta, swings)


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	body.call("_advance_motion", delta, swings)


func apply_swept_contact(hit: Dictionary) -> void:
	body.call("_apply_swept_contact", hit)


func contact_separation(hit: Dictionary) -> Vector2:
	return body.call("_contact_separation", hit)


func advance_default(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	super.advance_motion(delta, swings)


func apply_default(hit: Dictionary) -> void:
	super.apply_swept_contact(hit)


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
