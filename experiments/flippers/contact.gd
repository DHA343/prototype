extends RefCounted


static func complete_motion(
	target: CharacterBody2D, items: Array[PinballFlipper], swings: Array[PinballFlipper.Swing],
) -> Array[PinballFlipper.Swing]:
	var plans: Array[PinballFlipper.Swing] = swings.duplicate()
	for item: TableFlipper in items:
		if not item.visible or (item.collision_layer & target.collision_mask) == 0:
			continue
		var moving := false
		for swing: PinballFlipper.Swing in swings:
			if swing.flipper == item:
				moving = true
				break
		if not moving:
			plans.append(stationary_motion(item))
	return plans


static func stationary_motion(item: TableFlipper) -> PinballFlipper.Swing:
	var swing := PinballFlipper.Swing.new()
	swing.flipper = item
	swing.start_angle = item.rotation
	swing.speed = 0.0
	swing.stop_time = 0.0
	swing.parent_pose = (item.get_parent() as Node2D).global_transform
	swing.origin = item.global_position
	swing.reach = 0.0
	for point: Vector2 in item.world_polygon_at(item.global_transform):
		swing.reach = maxf(swing.reach, point.distance_to(swing.origin))
	return swing


static func query(
	item: TableFlipper, swing: PinballFlipper.Swing, center: Vector2,
	velocity: Vector2, radius: float, duration: float, equalization: float,
) -> Dictionary:
	var plan := stationary_motion(item) if swing == null else swing
	var hit := plan.sweep(center, velocity, radius, 0.0, duration, equalization)
	if hit.is_empty():
		return {"state": "none", "hit": {}}
	var state := "initial_overlap" if hit.time == 0.0 and hit.depth > 0.0001 else "contact"
	return {"state": state, "hit": hit}
