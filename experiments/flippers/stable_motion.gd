extends "res://experiments/flippers/tests/causal_motion.gd"

const Neighborhood = preload("res://experiments/flippers/stable_environment.gd")
const SafeRelease = preload("res://experiments/flippers/stable_release.gd")
const EnemyPath = preload("res://experiments/flippers/enemy_path.gd")

var refresh_clear_state: bool = true
var exact_native_time: bool = true
var relative_enemies: bool = true
var normal_all: bool = false
var bounded_clearance: bool = false
var finish_contacts: bool = false
var clear_tails: int = 0
var enemy_paths: Array[Dictionary] = []
var raw_queries: int = 0
var cap_snapshot: Dictionary = {}


func _init(target: CharacterBody2D) -> void:
	super(target)
	_observer = Neighborhood.new()


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	enemy_paths.clear()
	for node: Node in body.get_parent().get_children():
		if node is Enemy and node.active and node.collision_layer & body.collision_mask:
			var start: Vector2 = node.global_position
			var trace: Variant = node.get("trace")
			if trace is Dictionary and trace.has("before"):
				start = Vector2(trace.before[0], trace.before[1])
			elif relative_enemies:
				assert(node.velocity.is_zero_approx(), "Moving Enemy requires a start-of-tick snapshot")
			enemy_paths.append({"body": node, "start": start, "end": node.global_position,
				"velocity": (node.global_position - start) / delta})
			if trace is Dictionary and trace.has("segments"):
				assert(trace.raw_matches, "Enemy path query differed from actual movement")
				enemy_paths.back()["segments"] = trace.segments
	raw_queries = 0
	clear_tails = 0
	cap_snapshot = {}
	(_observer as Neighborhood).paths.clear()
	if relative_enemies:
		(_observer as Neighborhood).paths.append_array(enemy_paths)
	if recovery is SafeRelease:
		(recovery as SafeRelease).paths.clear()
		(recovery as SafeRelease).paths.append_array(enemy_paths)
	super.advance(delta, swings)
	if exact_native_time:
		discarded_seconds = maxf(0.0, delta - _elapsed) if events.size() == MAX_CONTACTS else 0.0


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	_refresh_clear()
	if not exact_native_time:
		super.advance_motion(delta, swings)
		return
	if recovery.failed:
		return
	var excluded: Array[Enemy] = []
	if relative_enemies:
		for path: Dictionary in enemy_paths:
			if path.body not in body.get_collision_exceptions():
				body.add_collision_exception_with(path.body)
				excluded.append(path.body)
	body.velocity = step_velocity(body.velocity, delta)
	_simulate(delta, swings)
	for enemy: Enemy in excluded:
		body.remove_collision_exception_with(enemy)


func _simulate(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	for index: int in MAX_CONTACTS:
		_refresh_clear()
		var remaining := delta - _elapsed
		var motion := body.velocity * remaining
		var parameters := PhysicsTestMotionParameters2D.new()
		parameters.from = body.global_transform
		parameters.motion = motion
		parameters.margin = CONTACT_MARGIN
		parameters.recovery_as_collision = true
		var raw := PhysicsTestMotionResult2D.new()
		var found := PhysicsServer2D.body_test_motion(body.get_rid(), parameters, raw)
		raw_queries += 1
		var native_time := remaining * raw.get_collision_safe_fraction() if found else remaining
		var enemy_hit := _enemy_contact(native_time) if relative_enemies else {}
		var limit: float = enemy_hit.get("time", native_time)
		var hit := {}
		if not swings.is_empty() and not flippers.is_target_disabled(body.get_instance_id()):
			hit = flippers.first_contact(swings, body.global_position, body.velocity,
				radius, _elapsed, limit)
		if not hit.is_empty() and (not found or hit.time < native_time) \
				and (enemy_hit.is_empty() or hit.time < enemy_hit.time):
			apply_swept_contact(hit)
		elif not enemy_hit.is_empty() and (not found or enemy_hit.time < native_time):
			_apply_enemy(enemy_hit)
		else:
			var before := body.global_position
			_before_time = _elapsed
			_elapsed += native_time
			var travel := _native_travel(raw, found, motion)
			body.global_position += travel
			body.force_update_transform()
			if not found:
				_elapsed = delta
				break
			_correction = travel - motion * raw.get_collision_safe_fraction()
			var actor := instance_from_id(raw.get_collider_id()) as PhysicsBody2D
			var point := raw.get_collision_point()
			var normal := raw.get_collision_normal()
			if finish_contacts:
				var depth := _depth(actor, body.global_position)
				if depth > 0.0:
					var extra := _bounded_offset(body.global_position,
						normal * (depth + SEPARATION_MARGIN), actor, _elapsed)
					body.global_position += extra
					body.force_update_transform()
					_correction += extra
			_kind = "native"
			_target = str(actor.name)
			_context = {"category": "native_contact", "tick_initial_overlap":
				_initial_overlaps.get(actor.get_instance_id(), false), "separation_policy": "Godot_raw",
				"raw_safe_fraction": raw.get_collision_safe_fraction(), "depth_px": raw.get_collision_depth()}
			_native_start_contact = {}
			_native_geometry = {"geometric_contact_depth_px":
				_depth(actor, before + motion * raw.get_collision_safe_fraction()),
				"post_separation_depth_px": _depth(actor, body.global_position)}
			_environment = _observer.observe(body, radius, actor,
				before + motion * raw.get_collision_safe_fraction(), _correction,
				flippers, _plans, _elapsed)
			if actor is PinballFlipper:
				var striking: bool = actor.is_striking(point, normal)
				_respond_to_flipper({"flipper": actor, "point": point, "normal": normal,
					"ratio": actor.contact_ratio(point), "is_striking": striking,
					"surface_velocity": actor.surface_velocity_at(point),
					"strike_surface_velocity": actor.surface_velocity_at(point,
						flippers.power_equalization if striking else 0)})
			else:
				var incoming := body.velocity
				_context["surface_velocity"] = _vec(actor.velocity if actor is Enemy else Vector2.ZERO)
				_native_response(actor, point, normal,
					actor.velocity if actor is Enemy else Vector2.ZERO)
				_record_event({"point": point, "normal": normal, "ratio": 0.0}, incoming, false)
			native_geometry.append({"target": str(actor.name), "iteration": index,
				"time_ms": _elapsed * 1000.0, "before_time_ms": _before_time * 1000.0,
				"raw_safe_fraction": raw.get_collision_safe_fraction(), "travel": _vec(travel),
				"recovery": _vec(_correction), "position": _vec(body.global_position),
				"geometry": _native_geometry.duplicate(), "velocity": _vec(body.velocity)})
			_previous_position = body.global_position
		body.velocity = body.velocity.limit_length(max_speed)
		if delta - _elapsed < 0.000001:
			break
	if finish_contacts and events.size() == MAX_CONTACTS and delta - _elapsed >= 0.000001:
		_try_clear_tail(delta, swings)
	if events.size() == MAX_CONTACTS and delta - _elapsed >= 0.000001:
		cap_snapshot = _constraints()


func _try_clear_tail(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	var remaining := delta - _elapsed
	var parameters := PhysicsTestMotionParameters2D.new()
	parameters.from = body.global_transform
	parameters.motion = body.velocity * remaining
	parameters.margin = CONTACT_MARGIN
	parameters.recovery_as_collision = true
	var raw := PhysicsTestMotionResult2D.new()
	raw_queries += 1
	if PhysicsServer2D.body_test_motion(body.get_rid(), parameters, raw):
		return
	if relative_enemies and not _enemy_contact(remaining).is_empty():
		return
	if not flippers.is_target_disabled(body.get_instance_id()) and not swings.is_empty():
		if not flippers.first_contact(swings, body.global_position, body.velocity,
				radius, _elapsed, remaining).is_empty():
			return
	body.global_position += _native_travel(raw, false, parameters.motion)
	body.force_update_transform()
	_elapsed = delta
	clear_tails += 1


func _native_travel(raw: PhysicsTestMotionResult2D, found: bool, motion: Vector2) -> Vector2:
	# Match PhysicsBody2D's cancel_sliding wrapper; time still uses the raw safe fraction.
	var precision := 0.001
	var length := motion.length()
	if found:
		precision += length * (raw.get_collision_unsafe_fraction() - raw.get_collision_safe_fraction())
		if raw.get_collision_depth() > CONTACT_MARGIN + precision:
			return raw.get_travel()
	var direction := motion.normalized()
	var projected := direction * raw.get_travel().dot(direction)
	return projected if (raw.get_travel() - projected).length() < CONTACT_MARGIN + precision else raw.get_travel()


func apply_swept_contact(hit: Dictionary) -> void:
	_refresh_clear()
	super.apply_swept_contact(hit)


func contact_separation(hit: Dictionary) -> Vector2:
	if not normal_all:
		return super.contact_separation(hit)
	_correction = hit.normal * (maxf(0.0, hit.depth) + SEPARATION_MARGIN)
	_context.separation_policy = "normal_all"
	var start: Vector2 = body.global_position + body.velocity * float(hit.time)
	if bounded_clearance:
		_correction = _bounded_offset(start, _correction, hit.flipper, _elapsed)
	var after: Dictionary = hit.flipper._contact_at(start + _correction, radius, hit.pose, 0.0, 0.0)
	_context["post_separation_overlap"] = not after.is_empty()
	_context["post_separation_depth_px"] = after.get("depth", 0.0)
	_environment = _observer.observe(body, radius, hit.flipper, start, _correction,
		flippers, _plans, _elapsed)
	return _correction


func _bounded_offset(start: Vector2, offset: Vector2, ignored: PhysicsBody2D, time: float) -> Vector2:
	var circle := CircleShape2D.new()
	circle.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, start)
	query.motion = offset
	query.collision_mask = body.collision_mask
	var excluded: Array[RID] = [body.get_rid(), ignored.get_rid()]
	for item: PinballFlipper in flippers.items:
		excluded.append(item.get_rid())
	for path: Dictionary in enemy_paths:
		excluded.append(path.body.get_rid())
	query.exclude = excluded
	var fraction: float = body.get_world_2d().direct_space_state.cast_motion(query)[0]
	if not flippers.is_target_disabled(body.get_instance_id()):
		for item: PinballFlipper in flippers.items:
			if item == ignored or item.collision_layer & body.collision_mask == 0:
				continue
			var polygon := ConvexPolygonShape2D.new()
			polygon.points = (item as TableFlipper).world_polygon_at(_pose_at(item, time))
			if circle.collide(Transform2D(0.0, start), polygon, Transform2D.IDENTITY):
				continue
			if circle.collide_with_motion(Transform2D(0.0, start), offset * fraction,
					polygon, Transform2D.IDENTITY, Vector2.ZERO):
				var lower := 0.0
				var upper := fraction
				for index: int in 16:
					var middle := (lower + upper) * 0.5
					if circle.collide_with_motion(Transform2D(0.0, start), offset * middle,
							polygon, Transform2D.IDENTITY, Vector2.ZERO):
						upper = middle
					else:
						lower = middle
				fraction = lower
	for path: Dictionary in enemy_paths:
		if not is_instance_valid(path.body) or not path.body.active or path.body == ignored:
			continue
		var difference := start - EnemyPath.position_at(path, time)
		var reach: float = radius + path.body.radius
		var a := offset.length_squared()
		var b := difference.dot(offset)
		var c := difference.length_squared() - reach * reach
		var discriminant := b * b - a * c
		if c > 0 and a > 0 and b < 0 and discriminant >= 0:
			fraction = minf(fraction, maxf(0.0, (-b - sqrt(discriminant)) / a))
	return offset * fraction


func _refresh_clear() -> void:
	if not refresh_clear_state:
		return
	for item: PinballFlipper in flippers.items:
		if item._contact_at(body.global_position, radius,
				_pose_at(item, _elapsed), 0.0, 0.0).is_empty():
			_initial_overlaps[item.get_instance_id()] = false


func _enemy_contact(limit: float) -> Dictionary:
	var result := {}
	for path: Dictionary in enemy_paths:
		var enemy: Enemy = path.body
		if not is_instance_valid(enemy) or not enemy.active:
			continue
		var intervals: Array = path.get("segments", [{"start_time": 0.0, "duration": INF}])
		for segment: Dictionary in intervals:
			var start_time := maxf(_elapsed, segment.start_time)
			var shift := start_time - _elapsed
			var duration := minf(limit - shift, segment.start_time + segment.duration - start_time)
			if shift > limit or duration < 0.0:
				continue
			var center := EnemyPath.position_at(path, start_time)
			var surface := EnemyPath.velocity_at(path, start_time)
			var difference := body.global_position + body.velocity * shift - center
			var velocity := body.velocity - surface
			var reach := radius + enemy.radius
			var depth := reach - difference.length()
			var time := 0.0
			if depth < 0.0:
				var a := velocity.length_squared()
				var b := difference.dot(velocity)
				var c := difference.length_squared() - reach * reach
				var discriminant := b * b - a * c
				if a == 0.0 or b >= 0.0 or discriminant < 0.0:
					continue
				time = (-b - sqrt(discriminant)) / a
				if time < 0.0 or time > duration:
					continue
			var offset := difference + velocity * time
			var normal := offset.normalized() if not offset.is_zero_approx() else Vector2.UP
			result = {"time": shift + time, "normal": normal, "enemy": enemy,
				"point": center + surface * time + normal * enemy.radius,
				"surface_velocity": surface, "depth": maxf(0.0, reach - offset.length())}
			limit = shift + time
	return result


func _apply_enemy(hit: Dictionary) -> void:
	_before_time = _elapsed
	_elapsed += hit.time
	var incoming := body.velocity
	var before: Vector2 = body.global_position + incoming * hit.time
	_correction = hit.normal * (float(hit.depth) + SEPARATION_MARGIN)
	if bounded_clearance:
		_correction = _bounded_offset(before, _correction, hit.enemy, _elapsed)
	body.global_position = before + _correction
	body.force_update_transform()
	_kind = "enemy_relative"
	_target = str(hit.enemy.name)
	_context = {"category": "enemy_relative", "separation_policy": "normal",
		"depth_px": hit.depth, "surface_velocity": _vec(hit.surface_velocity)}
	_environment = _observer.observe(body, radius, hit.enemy, before, _correction,
		flippers, _plans, _elapsed)
	_native_response(hit.enemy, hit.point, hit.normal, hit.surface_velocity)
	_record_event({"point": hit.point, "normal": hit.normal, "ratio": 0.0}, incoming, false)
	_previous_position = body.global_position


func _native_response(actor: PhysicsBody2D, point: Vector2, normal: Vector2, surface: Vector2) -> void:
	var ball := body as PinballBall
	var incoming := -(body.velocity - surface).dot(normal)
	if incoming <= 0.0:
		return
	var speed := body.velocity.length()
	var enemy := actor as Enemy
	var restitution := enemy.restitution if enemy != null else boundary.restitution_for(actor)
	if actor is PinballBumper:
		body.velocity += normal * (incoming + maxf(incoming * restitution, actor.exit_speed))
		if incoming > 30:
			actor.hit(point)
	else:
		body.velocity = reflected_velocity(body.velocity, normal, restitution, surface)
	if enemy != null and speed > 30 and enemy not in ball._enemy_contacts:
		ball._enemy_contacts.append(enemy)
		enemy.receive_hit(ball.damage + speed * ball.damage_per_speed, point,
			-normal * (ball.knockback + speed * ball.knockback_per_speed))
		if ball.hit_sound != null:
			ball.sound_requested.emit(SoundRequest.new(ball.hit_sound, point, ball))
	if incoming > 30:
		ball._record_contact(point, normal)


func _record_event(hit: Dictionary, incoming: Vector2, shot: bool) -> void:
	super._record_event(hit, incoming, shot)
	var event: Dictionary = events.back()
	var item: PinballFlipper = hit.get("flipper")
	if item != null:
		event["original_tick_contact"] = not item._contact_at(_tick_start, radius,
			_pose_at(item, 0.0), 0.0, 0.0).is_empty()
	var introduced_depth := 0.0
	for entry: Dictionary in event.environment.get("introduced", []):
		var actor := instance_from_id(int(entry.id)) as PhysicsBody2D
		var depth := _depth(actor, body.global_position)
		if actor is Enemy and relative_enemies:
			for path: Dictionary in enemy_paths:
				if path.body == actor:
					var center := EnemyPath.position_at(path, _elapsed)
					depth = maxf(0.0, radius + actor.radius - center.distance_to(body.global_position))
		elif actor is PinballFlipper:
			depth = actor._contact_at(body.global_position, radius,
				_pose_at(actor, _elapsed), 0.0, 0.0).get("depth", 0.0)
		entry["depth_px"] = depth
		introduced_depth = maxf(introduced_depth, depth)
	event["introduced_depth_max_px"] = introduced_depth


func _constraints() -> Dictionary:
	var planes: Array[Dictionary] = []
	var center := body.global_position
	for path: Dictionary in enemy_paths:
		if not is_instance_valid(path.body) or not path.body.active:
			continue
		var position: Vector2 = EnemyPath.position_at(path, _elapsed) if relative_enemies else path.end
		var difference := center - position
		var depth: float = radius + path.body.radius - difference.length()
		if depth >= -CONTACT_MARGIN:
			planes.append({"target": str(path.body.name), "normal": difference.normalized(),
				"surface": EnemyPath.velocity_at(path, _elapsed) if relative_enemies else path.body.velocity,
				"depth_px": depth})
	if not flippers.is_target_disabled(body.get_instance_id()):
		for item: PinballFlipper in flippers.items:
			if item.collision_layer & body.collision_mask == 0:
				continue
			var omega := 0.0
			for plan: PinballFlipper.Swing in _plans:
				if plan.flipper == item and _elapsed < plan.stop_time:
					omega = plan.speed
			var hit := item._contact_at(center, radius + CONTACT_MARGIN,
				_pose_at(item, _elapsed), omega, 0.0)
			if not hit.is_empty():
				planes.append({"target": str(item.name), "normal": hit.normal,
					"surface": hit.surface_velocity, "depth_px": hit.depth - CONTACT_MARGIN})
	var circle := CircleShape2D.new()
	circle.radius = radius + CONTACT_MARGIN
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = circle
	query.transform = Transform2D(0.0, center)
	query.collision_mask = body.collision_mask & 2
	var excluded: Array[RID] = []
	for item: PinballFlipper in flippers.items:
		excluded.append(item.get_rid())
	query.exclude = excluded
	for entry: Dictionary in body.get_world_2d().direct_space_state.intersect_shape(query, 128):
		var actor := entry.collider as PhysicsBody2D
		if actor is PinballBumper:
			var difference := center - actor.global_position
			planes.append({"target": str(actor.name), "normal": difference.normalized(),
				"surface": Vector2.ZERO, "depth_px": radius + actor.radius - difference.length()})
			continue
		var collision := actor.get_child(0) as CollisionShape2D
		var segments := collision.shape as ConcavePolygonShape2D
		if segments == null:
			continue
		for index: int in range(0, segments.segments.size(), 2):
			var point := Geometry2D.get_closest_point_to_segment(center,
				collision.to_global(segments.segments[index]),
				collision.to_global(segments.segments[index + 1]))
			var difference := center - point
			if difference.length() <= radius + CONTACT_MARGIN:
				planes.append({"target": str(actor.name), "normal": difference.normalized(),
					"surface": Vector2.ZERO, "depth_px": radius - difference.length()})
	var candidates: Array[Vector2] = [Vector2.ZERO]
	for plane: Dictionary in planes:
		candidates.append(plane.normal * (plane.surface as Vector2).dot(plane.normal))
	for left: int in planes.size():
		for right: int in range(left + 1, planes.size()):
			var a: Vector2 = planes[left].normal
			var b: Vector2 = planes[right].normal
			var determinant := a.cross(b)
			if is_zero_approx(determinant):
				continue
			var first: float = a.dot(planes[left].surface)
			var second: float = b.dot(planes[right].surface)
			candidates.append(Vector2(first * b.y - second * a.y,
				a.x * second - b.x * first) / determinant)
	var minimum := INF
	for velocity: Vector2 in candidates:
		var feasible := true
		for plane: Dictionary in planes:
			var value: float = (velocity - plane.surface).dot(plane.normal)
			feasible = feasible and (value >= 0.0 or is_zero_approx(value))
		if feasible:
			minimum = minf(minimum, velocity.length())
	for plane: Dictionary in planes:
		plane.normal = _vec(plane.normal)
		plane.surface = _vec(plane.surface)
	return {"position": _vec(center), "velocity": _vec(body.velocity), "time_ms": _elapsed * 1000.0,
		"planes": planes, "minimum_nonapproach_speed": minimum if is_finite(minimum) else null,
		"within_speed_limit": minimum <= max_speed}
