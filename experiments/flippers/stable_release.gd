extends "res://experiments/flippers/tests/causal_release.gd"

const EnemyPath = preload("res://experiments/flippers/enemy_path.gd")

var paths: Array[Dictionary] = []
var use_tangents: bool = false
var _observation_time: float = 0.0


func refresh(next_velocity_y: float) -> void:
	_observation_time = 0.0
	super.refresh(next_velocity_y)
	_observation_time = _duration


func world_contacts(center: Vector2, extra: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hit: Dictionary in super.world_contacts(center, extra):
		if hit.kind != "enemy":
			result.append(hit)
	for path: Dictionary in paths:
		if not is_instance_valid(path.body) or not path.body.active:
			continue
		var position := EnemyPath.position_at(path, _observation_time)
		if center.distance_to(position) < radius + path.body.radius + extra:
			result.append({"name": str(path.body.name), "id": str(path.body.get_instance_id()),
				"kind": "enemy"})
	return result


func safe_offset(hits: Array[Dictionary]) -> Dictionary:
	var directions: Array[Vector2] = []
	for hit: Dictionary in hits:
		directions.append(hit.normal)
	if use_tangents:
		for path: Dictionary in paths:
			var toward := EnemyPath.position_at(path, 0.0) - body.global_position
			var reach: float = radius + path.body.radius + CLEARANCE
			if toward.length() <= reach:
				continue
			var angle := asin(reach / toward.length())
			directions.append(toward.normalized().rotated(angle))
			directions.append(toward.normalized().rotated(-angle))
	var candidates: Array[Vector2] = []
	for direction: Vector2 in directions:
		var allowed := true
		for hit: Dictionary in hits:
			allowed = allowed and direction.dot(hit.normal) >= -0.0001
		if not allowed:
			continue
		var upper := 0.0
		for hit: Dictionary in hits:
			for point: Vector2 in (hit.flipper as TableFlipper).world_polygon_at(hit.pose):
				upper = maxf(upper, body.global_position.distance_to(point) + radius + CLEARANCE)
		var lower := 0.0
		for index: int in 16:
			var middle := (lower + upper) * 0.5
			if contacts(body.global_position + direction * middle, CLEARANCE).is_empty():
				upper = middle
			else:
				lower = middle
		candidates.append(direction * upper)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.length_squared() < b.length_squared())
	for offset: Vector2 in candidates:
		var reason := world_safety(offset, hits)
		if not contacts(body.global_position + offset, WORLD_MARGIN).is_empty():
			reason = "flipper_endpoint"
		tick.candidates.append({"offset": [offset.x, offset.y], "distance_px": offset.length(),
			"rejected": reason})
		if reason.is_empty():
			return {"found": true, "offset": offset}
	return {"found": false}


func world_safety(offset: Vector2, initial: Array[Dictionary]) -> String:
	var query := PhysicsShapeQueryParameters2D.new()
	_circle.radius = radius + WORLD_MARGIN
	query.shape = _circle
	query.transform = Transform2D(0.0, body.global_position)
	query.collision_mask = body.collision_mask
	var excluded: Array[RID] = [body.get_rid()]
	for item: PinballFlipper in flippers.items:
		excluded.append(item.get_rid())
	for path: Dictionary in paths:
		excluded.append(path.body.get_rid())
	query.exclude = excluded
	var space := body.get_world_2d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return "initial_static_overlap"
	query.transform.origin += offset
	if not space.intersect_shape(query, 1).is_empty():
		return "world_endpoint"
	query.transform.origin -= offset
	query.motion = offset
	if space.cast_motion(query)[0] < 1.0:
		return "world_path"
	for path: Dictionary in paths:
		var position := EnemyPath.position_at(path, 0.0)
		var nearest := Geometry2D.get_closest_point_to_segment(position,
			body.global_position, body.global_position + offset)
		if nearest.distance_to(position) < radius + path.body.radius + WORLD_MARGIN:
			return "enemy_path"
	for item: PinballFlipper in flippers.items:
		if item.collision_layer & body.collision_mask == 0:
			continue
		if initial.any(func(hit: Dictionary) -> bool: return hit.flipper == item):
			continue
		var polygon := ConvexPolygonShape2D.new()
		polygon.points = (item as TableFlipper).world_polygon_at(pose_at(item))
		if _circle.collide_with_motion(Transform2D(0.0, body.global_position), offset,
				polygon, Transform2D.IDENTITY, Vector2.ZERO):
			return "other_flipper_path"
	return ""
