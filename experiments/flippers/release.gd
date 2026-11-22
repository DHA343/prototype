extends RefCounted

enum Policy { CURRENT, POSTPONE, SAFE }

const Manager = preload("res://experiments/flippers/release_flippers.gd")
const CLEARANCE: float = 0.151
const WORLD_MARGIN: float = 0.03
const QUERY_LIMIT: int = 128

var policy: Policy = Policy.CURRENT
var limit: float = 3.0
var distance_limited: bool = true
var diagnostics: bool = true
var failed: bool = false
var tick: Dictionary = {}
var body: CharacterBody2D
var radius: float
var flippers: PinballFlippers
var _plans: Array[PinballFlipper.Swing] = []
var _duration: float = 0.0
var _waiting: float = 0.0
var _pending: bool = false
var _circle: CircleShape2D = CircleShape2D.new()


func reset() -> void:
	failed = false
	_waiting = 0.0
	_pending = false
	tick = {}


func begin(
	target: CharacterBody2D, size: float, manager: PinballFlippers,
	plans: Array[PinballFlipper.Swing], duration: float,
) -> void:
	body = target
	radius = size
	flippers = manager
	_plans = plans
	if _pending:
		_waiting += _duration
	_duration = duration
	tick = {}
	(manager as Manager).attach(body, self)


func contacts(center: Vector2, extra: float = 0.0, time: float = 0.0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: PinballFlipper in flippers.items:
		if not item.visible or (item.collision_layer & body.collision_mask) == 0:
			continue
		var hit := item._contact_at(center, radius + extra, pose_at(item, time), 0.0, 0.0)
		if not hit.is_empty():
			hit["flipper"] = item
			result.append(hit)
	return result


func pose_at(item: PinballFlipper, time: float = 0.0) -> Transform2D:
	for plan: PinballFlipper.Swing in _plans:
		if plan.flipper == item:
			return plan.parent_pose * Transform2D(
				plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
	return item.global_transform


func refresh(next_velocity_y: float) -> void:
	if failed or not flippers.is_target_disabled(body.get_instance_id()):
		return
	if next_velocity_y <= 1.0:
		return
	if policy == Policy.CURRENT and not diagnostics:
		flippers.release_target(body.get_instance_id())
		tick = {"requested": true, "released": true}
		_pending = false
		_waiting = 0.0
		return
	var hits := contacts(body.global_position)
	tick = {"requested": true, "overlapping": not hits.is_empty(), "released": false,
		"deferred": false, "failed": false, "correction": [0.0, 0.0],
		"delay_ms": _waiting * 1000.0, "before": [body.global_position.x, body.global_position.y],
		"next_velocity_y": next_velocity_y, "limit_px": limit if distance_limited else null,
		"contacts": [], "candidates": []}
	if diagnostics:
		tick["world_before"] = world_contacts(body.global_position)
		for hit: Dictionary in hits:
			var item: TableFlipper = hit.flipper
			var faces: Array[String] = []
			var polygon := item.world_polygon_at(hit.pose)
			for index: int in 4:
				if Geometry2D.get_closest_point_to_segment(hit.point, polygon[index],
					polygon[(index + 1) % 4]).distance_squared_to(hit.point) < 0.000004:
					faces.append(["top", "right", "bottom", "left"][index])
			tick.contacts.append({"target": str(item.name), "depth_px": hit.depth,
				"normal": [hit.normal.x, hit.normal.y], "faces": faces,
				"moving": _plans.any(func(plan: PinballFlipper.Swing) -> bool:
					return plan.flipper == item and plan.stop_time > 0.0),
				"point": [hit.point.x, hit.point.y]})
	if policy == Policy.POSTPONE and not hits.is_empty():
		if not _pending:
			_pending = true
			_waiting = 0.0
		tick.deferred = true
		tick.delay_ms = _waiting * 1000.0
		return
	if policy == Policy.SAFE and not hits.is_empty():
		var solution := safe_offset(hits)
		if not solution.found:
			failed = true
			tick.failed = true
			return
		var offset: Vector2 = solution.offset
		body.global_position += offset
		body.force_update_transform()
		tick.correction = [offset.x, offset.y]
		if diagnostics:
			tick["after_correction"] = [body.global_position.x, body.global_position.y]
			tick["flipper_clear_after"] = contacts(body.global_position, 0.03).is_empty()
			tick["world_after"] = world_contacts(body.global_position)
	flippers.release_target(body.get_instance_id())
	tick.released = true
	_pending = false
	_waiting = 0.0


func world_contacts(center: Vector2, extra: float = 0.0) -> Array[Dictionary]:
	var circle := CircleShape2D.new()
	circle.radius = radius + extra
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = body.collision_mask
	query.collide_with_areas = false
	var excluded: Array[RID] = [body.get_rid()]
	for item: PinballFlipper in flippers.items:
		excluded.append(item.get_rid())
	for actor: PhysicsBody2D in body.get_collision_exceptions():
		if not excluded.has(actor.get_rid()):
			excluded.append(actor.get_rid())
	query.exclude = excluded
	var result: Array[Dictionary] = []
	for hit: Dictionary in body.get_world_2d().direct_space_state.intersect_shape(query, QUERY_LIMIT):
		result.append({"name": str(hit.collider.name), "id": str(hit.collider_id),
			"kind": "enemy" if hit.collider is Enemy else "world", "shape": hit.shape})
	return result


func safe_offset(hits: Array[Dictionary]) -> Dictionary:
	var candidates: Array[Vector2] = []
	var left := 0.0
	var right := 0.0
	var up := 0.0
	var down := 0.0
	var center := body.global_position
	for hit: Dictionary in hits:
		candidates.append((hit.normal as Vector2) * (float(hit.depth) + CLEARANCE))
		var polygon := (hit.flipper as TableFlipper).world_polygon_at(hit.pose)
		for point: Vector2 in polygon:
			left = maxf(left, center.x - point.x + radius + CLEARANCE)
			right = maxf(right, point.x - center.x + radius + CLEARANCE)
			up = maxf(up, center.y - point.y + radius + CLEARANCE)
			down = maxf(down, point.y - center.y + radius + CLEARANCE)
	candidates.append_array([Vector2.LEFT * left, Vector2.RIGHT * right,
		Vector2.UP * up, Vector2.DOWN * down])
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.length_squared() < b.length_squared())
	for offset: Vector2 in candidates:
		var reason := ""
		if distance_limited and offset.length() > limit:
			reason = "limit"
		elif not contacts(center + offset, 0.03).is_empty():
			reason = "flipper_endpoint"
		else:
			for hit: Dictionary in hits:
				if offset.dot(hit.normal) < -0.0001:
					reason = "deeper_into_flipper"
			if reason.is_empty():
				reason = world_safety(offset, hits)
		if diagnostics:
			var entry := {"offset": [offset.x, offset.y], "distance_px": offset.length(), "rejected": reason}
			if reason == "world_endpoint":
				entry["blocked_by"] = world_contacts(center + offset, WORLD_MARGIN)
			tick.candidates.append(entry)
		if reason.is_empty():
			return {"found": true, "offset": offset}
	return {"found": false}


func world_safety(offset: Vector2, initial: Array[Dictionary]) -> String:
	_circle.radius = radius + WORLD_MARGIN
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = _circle
	query.collision_mask = body.collision_mask
	query.collide_with_areas = false
	var excluded: Array[RID] = [body.get_rid()]
	for item: PhysicsBody2D in body.get_collision_exceptions():
		excluded.append(item.get_rid())
	for item: PinballFlipper in flippers.items:
		if not excluded.has(item.get_rid()):
			excluded.append(item.get_rid())
	query.exclude = excluded
	var space := body.get_world_2d().direct_space_state
	query.transform = Transform2D(0.0, body.global_position)
	var before := space.intersect_shape(query, QUERY_LIMIT)
	if before.size() == QUERY_LIMIT:
		return "query_limit"
	query.transform.origin += offset
	if not space.intersect_shape(query, 1).is_empty():
		return "world_endpoint"
	query.transform.origin -= offset
	query.motion = offset
	if space.cast_motion(query)[0] < 1.0:
		return "world_path"
	for overlap: Dictionary in before:
		var actor := overlap.collider as CollisionObject2D
		var owner := actor.shape_find_owner(int(overlap.shape))
		var shape: Shape2D
		for index: int in actor.shape_owner_get_shape_count(owner):
			if actor.shape_owner_get_shape_index(owner, index) == int(overlap.shape):
				shape = actor.shape_owner_get_shape(owner, index)
		if shape is ConcavePolygonShape2D or shape == null:
			return "unsupported_initial_shape"
		var pairs := _circle.collide_and_get_contacts(Transform2D(0.0, body.global_position),
			shape, (actor as Node2D).global_transform * actor.shape_owner_get_transform(owner))
		for index: int in range(0, pairs.size(), 2):
			if offset.dot(pairs[index + 1] - pairs[index]) < -0.0001:
				return "deeper_into_world"
	for item: PinballFlipper in flippers.items:
		if not item.visible or (item.collision_layer & body.collision_mask) == 0:
			continue
		if initial.any(func(hit: Dictionary) -> bool: return hit.flipper == item):
			continue
		var polygon := ConvexPolygonShape2D.new()
		polygon.points = (item as TableFlipper).world_polygon_at(pose_at(item))
		if _circle.collide_with_motion(Transform2D(0.0, body.global_position), offset,
			polygon, Transform2D.IDENTITY, Vector2.ZERO):
			return "other_flipper_path"
	return ""
