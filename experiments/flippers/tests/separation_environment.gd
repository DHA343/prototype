extends RefCounted

const LIMIT: int = 128

var _circle: CircleShape2D = CircleShape2D.new()


func observe(
	body: CharacterBody2D, radius: float, ignored: PhysicsBody2D,
	start: Vector2, offset: Vector2, flippers: PinballFlippers,
	plans: Array[PinballFlipper.Swing], time: float,
) -> Dictionary:
	_circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _circle
	query.margin = 0.0
	query.collision_mask = body.collision_mask
	query.collide_with_areas = false
	var excluded: Array[RID] = [body.get_rid()]
	if ignored != null:
		excluded.append(ignored.get_rid())
	for item: PhysicsBody2D in body.get_collision_exceptions():
		if not excluded.has(item.get_rid()):
			excluded.append(item.get_rid())
	for item: PinballFlipper in flippers.items:
		if not excluded.has(item.get_rid()):
			excluded.append(item.get_rid())
	query.exclude = excluded
	var space := body.get_world_2d().direct_space_state
	query.transform = Transform2D(0.0, start)
	var raw_before := space.intersect_shape(query, LIMIT)
	var before := _actors(raw_before)
	query.transform = Transform2D(0.0, start + offset)
	var raw_after := space.intersect_shape(query, LIMIT)
	var after := _actors(raw_after)
	query.transform = Transform2D(0.0, start)
	query.motion = offset
	var fractions := space.cast_motion(query)
	var path_blocked := fractions[0] < 1.0
	var nearby: Array[Dictionary] = []
	if path_blocked:
		query.transform = Transform2D(0.0, start + offset * fractions[1])
		query.motion = Vector2.ZERO
		query.margin = 0.0001
		nearby = _actors(space.intersect_shape(query, LIMIT))
	var plate_paths: Array[String] = []
	if not flippers.is_target_disabled(body.get_instance_id()):
		for item: PinballFlipper in flippers.items:
			if item == ignored or not item.visible or (item.collision_layer & body.collision_mask) == 0:
				continue
			var table := item as TableFlipper
			var polygon := ConvexPolygonShape2D.new()
			polygon.points = table.world_polygon_at(_pose_at(item, plans, time))
			var actor := {"id": str(item.get_instance_id()), "name": str(item.name), "kind": "flipper"}
			if _circle.collide(Transform2D(0.0, start), polygon, Transform2D.IDENTITY):
				before.append(actor)
			if _circle.collide(Transform2D(0.0, start + offset), polygon, Transform2D.IDENTITY):
				after.append(actor)
			if _circle.collide_with_motion(Transform2D(0.0, start), offset,
				polygon, Transform2D.IDENTITY, Vector2.ZERO):
				path_blocked = true
				plate_paths.append(str(item.name))
	var before_ids: Array = before.map(func(actor: Dictionary) -> String: return actor.id)
	var introduced: Array = after.filter(func(actor: Dictionary) -> bool: return not before_ids.has(actor.id))
	return {"before": before, "after": after, "introduced": introduced,
		"path_blocked": path_blocked, "path_only": path_blocked and before.is_empty() and after.is_empty(),
		"safe_fraction": fractions[0], "unsafe_fraction": fractions[1],
		"near_unsafe": nearby, "other_flipper_paths": plate_paths,
		"limited": raw_before.size() == LIMIT or raw_after.size() == LIMIT,
		"time_ms": time * 1000.0, "margin": 0.0}


func _actors(hits: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var ids: Array[String] = []
	for hit: Dictionary in hits:
		var actor := hit.collider as PhysicsBody2D
		var id := str(actor.get_instance_id())
		if ids.has(id):
			continue
		ids.append(id)
		result.append({"id": id, "name": str(actor.name),
			"kind": "enemy" if actor is Enemy else "world", "shape": hit.shape})
	return result


func _pose_at(item: PinballFlipper, plans: Array[PinballFlipper.Swing], time: float) -> Transform2D:
	for plan: PinballFlipper.Swing in plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
	return item.global_transform
