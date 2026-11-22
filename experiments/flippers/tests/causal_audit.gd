extends "res://experiments/flippers/tests/unlimited_audit.gd"

const CausalMotion = preload("res://experiments/flippers/tests/causal_motion.gd")
const CausalEnemy = preload("res://experiments/flippers/tests/causal_enemy.gd")
const ENVIRONMENTS: Array[Dictionary] = [
	{"name": "flipper_only", "world": "none", "enemies": 0},
	{"name": "walls", "world": "walls", "enemies": 0},
	{"name": "enemy", "world": "none", "enemies": 1},
	{"name": "enemy_frozen", "world": "none", "enemies": 1, "frozen": true},
	{"name": "three_static_spacing", "world": "none", "enemies": 3, "spacing": 62.0},
	{"name": "three_crowd_dense", "world": "none", "enemies": 3, "spacing": 62.0, "crowd": true},
	{"name": "three_crowd_sparse", "world": "none", "enemies": 3, "spacing": 86.0, "crowd": true},
	{"name": "walls_enemy", "world": "walls", "enemies": 1},
	{"name": "walls_enemy_frozen", "world": "walls", "enemies": 1, "frozen": true},
	{"name": "walls_three_crowd", "world": "walls", "enemies": 3, "spacing": 62.0, "crowd": true},
	{"name": "full_reference", "world": "full", "enemies": 1},
	{"name": "full_routes_crowd", "world": "full", "enemies": 3, "spacing": 62.0, "crowd": true, "routes": true},
]
const FOCUS: Array[Vector3] = [Vector3(.5, 36, 0), Vector3(.7, 36, 0), Vector3(.9, 3, 0),
	Vector3(.15, 3, 0), Vector3(.99, 12, 36), Vector3(.9, 3, 36),
	Vector3(.9, 12, 36), Vector3(.99, 3, 36), Vector3(.7, 36, 36)]

var _static_bodies: Array[Dictionary] = []
var _actors: Array[Enemy] = []
var _step_context: Dictionary = {}
var _full_events: bool = false


func _make_main(counted: bool) -> void:
	super._make_main(counted)
	for node: Node in _main.get_node("Playfield").find_children("*", "", true, false):
		if node is PinballBumper:
			node.hit_sound = null


func _run() -> void:
	_read_inputs()
	var hashes := _production_hashes()
	for path: String in ["enemies/crowd.gd", "enemies/routes.gd", "pinball/boundary.gd",
		"enemies/enemy.tscn", "pinball/flipper.tscn"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	var layers := _layers()
	var conformance := await _enemy_conformance()
	var matrix := {}
	for config: Dictionary in [TRIALS[0], TRIALS[2]]:
		_config = config
		matrix[config.name] = {}
		for environment: Dictionary in ENVIRONMENTS:
			var cases: Array[Dictionary] = []
			for ratio: float in [.05, .15, .30, .50, .70, .90, .99]:
				for gap: float in [3, 12, 36, 72]:
					for offset: float in [-36, 0, 36]:
						cases.append(await _scenario(Vector3(ratio, gap, offset), environment))
			var filename: String = "causal_" + str(config.name) + "_" + str(environment.name) + ".json"
			_write(filename, {"cases": cases})
			matrix[config.name][environment.name] = filename
			print("Causal environment: ", config.name, ":", environment.name)
	_write("causal_environments.json", {"checks": _checks, "failures": _failures, "matrix": matrix})
	var normal: Array[Dictionary] = []
	_config = TRIALS[0]
	for environment: Dictionary in [ENVIRONMENTS[1], ENVIRONMENTS[2], ENVIRONMENTS[7],
		ENVIRONMENTS[8], ENVIRONMENTS[9], ENVIRONMENTS[11]]:
		for ratio: float in [.05, .15, .30, .50, .70, .90, .99]:
			for gap: float in [3, 12, 36, 72]:
				for offset: float in [-36, 0, 36]:
					normal.append(await _scenario(Vector3(ratio, gap, offset), environment, true))
	print("Causal ordinary collisions: ", normal.size())
	var checkpoints: Array[Dictionary] = []
	_full_events = true
	for config: Dictionary in [TRIALS[0], TRIALS[2]]:
		_config = config
		for fixture: Vector3 in FOCUS:
			var frame := 2 if fixture in [FOCUS[0], FOCUS[1], FOCUS[8]] else 1
			for environment: Dictionary in [ENVIRONMENTS[0], ENVIRONMENTS[1], ENVIRONMENTS[2],
				ENVIRONMENTS[8], ENVIRONMENTS[10]]:
				checkpoints.append(await _scenario(fixture, environment, false, frame))
	_full_events = false
	var normal_pairs: Array[Dictionary] = []
	_full_events = true
	_config = TRIALS[0]
	for prefix: Dictionary in [ENVIRONMENTS[9], ENVIRONMENTS[11]]:
		for gap: float in [3, 12]:
			for probe: String in ["control", "surface_velocity_zero", "enemy_excluded"]:
				var environment := prefix.duplicate()
				environment.name = str(prefix.name) + ":" + probe
				environment.frozen = probe == "surface_velocity_zero"
				environment.enemies = 0 if probe == "enemy_excluded" else 3
				normal_pairs.append(await _scenario(Vector3(.05, gap, -36), environment,
					true, 2 if gap == 3 else 5, prefix))
	_full_events = false
	_world("full")
	var regression := _unlimited_regression()
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production source changed")
	_main.free()
	_write("causal_audit.json", {"checks": _checks, "failures": _failures,
		"normal": normal, "normal_pairs": normal_pairs, "checkpoints": checkpoints, "layers": layers,
		"enemy_conformance": conformance, "regression": regression, "production_sha256": hashes,
		"scope": "Observation only. Environment ablations and pre-ball paired interventions; no response, direction, guard, or iteration fixes."})
	print("Causal checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := CausalMotion.new(ball)
	recorder.normal_for_new_contact = _config.separation
	recorder.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	recorder.recovery.limit = _config.limit
	recorder.recovery.distance_limited = not _config.get("unlimited", false)
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _result(recorder: Trace, cpu: int = 0) -> Dictionary:
	var result := super._result(recorder, cpu)
	var trace := recorder as CausalMotion
	result["stages"] = trace.recovery.get("stages").duplicate(true)
	result.stages.append_array(trace.stages.duplicate(true))
	result["native_geometry"] = trace.native_geometry.duplicate(true)
	return result


func _world(mode: String) -> void:
	for saved: Dictionary in _static_bodies:
		var boundary := _main.boundary.is_ancestor_of(saved.node)
		saved.node.collision_layer = saved.layer if mode == "full" or (mode == "walls" and boundary) else 0


func _new_enemy(position: Vector2, routes: bool = false) -> Enemy:
	var actor := load("res://enemies/enemy.tscn").instantiate() as Enemy
	var values := {}
	for property: Dictionary in actor.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_STORAGE:
			values[property.name] = actor.get(property.name)
	actor.set_script(CausalEnemy)
	for key: String in values:
		actor.set(key, values[key])
	actor.position = position
	actor.death_cue = null
	_main.get_node("Playfield").add_child(actor)
	actor.prepare(actor.grow_duration)
	(actor as CausalEnemy).trace_enabled = true
	if routes:
		actor.start(_main.routes)
	return actor


func _scenario(
	input: Vector3, environment: Dictionary, ordinary: bool = false,
	checkpoint: int = -1, prefix: Dictionary = {},
) -> Dictionary:
	_actors.clear()
	_set_rule(2)
	_reset_integration()
	var actual: Dictionary = environment
	if checkpoint >= 0:
		actual = ENVIRONMENTS[10] if prefix.is_empty() else prefix
	_world(actual.world)
	if actual.get("guard_off", false):
		_main.flippers.pass_until_descending = false
	if ordinary:
		_main.flippers.pass_until_descending = false
		for item: PinballFlipper in _main.flippers.items:
			item.collision_layer = 0
	var points := (_main.flippers.items[0] as TableFlipper).world_polygon_at(_main.flippers.items[0].global_transform)
	_main.ball.reset_at(points[0].lerp(points[1], input.x) + Vector2.UP * 28,
		Vector2(0, -1800 if ordinary else 300))
	var start := _main.ball.global_position
	var primary := start + Vector2(input.z, -(54.0 + input.y))
	for index: int in int(actual.enemies):
		var spacing: float = actual.get("spacing", 62.0)
		var offset := Vector2(0, 0) if index == 0 else Vector2((-1 if index == 1 else 1) * spacing, 0)
		_actors.append(_new_enemy(primary + offset, actual.get("routes", false)))
	await physics_frame
	var result := _new_result({"ratio": input.x, "gap": input.y, "offset": input.z,
		"policy": _config.name, "environment": environment.name, "ordinary": ordinary, "checkpoint": checkpoint,
		"guard_enabled": _main.flippers.pass_until_descending,
		"initial": _snapshot(), "pre_ball_overlap_updates": 0, "enemy_budget_updates": 0,
		"initial_ball_overlap": _obstacles(_main.ball, _main.ball.radius, 6),
		"initial_enemy_overlap": [], "enemy_residual_updates": 0, "enemy_residual_max_px": 0.0,
		"enemy_contacts": 0, "max_crowd_request_px": 0.0, "important": []})
	for actor: Enemy in _actors:
		result.initial_enemy_overlap.append(_obstacles(actor, actor.radius))
	for frame: int in 60:
		var plans := _main.flippers.plan_motion(true, true)
		_main.flippers.advance(1.0 / 60.0, true, true)
		for index: int in range(_actors.size() - 1, -1, -1):
			if not is_instance_valid(_actors[index]) or not _actors[index].active:
				_actors.remove_at(index)
		for actor: Enemy in _actors:
			actor.prepare(1.0 / 60.0)
		if actual.get("crowd", false):
			_main.crowd.calculate(_actors, 1.0 / 60.0, _main.boundary.exit_target())
		var enemies: Array[Dictionary] = []
		for actor: Enemy in _actors:
			result.max_crowd_request_px = maxf(result.max_crowd_request_px, actor.crowd_motion.length())
			if actual.get("frozen", false):
				actor.velocity = Vector2.ZERO
				(actor as CausalEnemy).trace = {}
			else:
				actor.advance(1.0 / 60.0)
			var trace: Dictionary = (actor as CausalEnemy).trace
			trace["world_after"] = _obstacles(actor, actor.radius)
			for overlap: Dictionary in trace.world_after:
				result.enemy_residual_updates += int(overlap.depth_px > 0.0)
				result.enemy_residual_max_px = maxf(result.enemy_residual_max_px, overlap.depth_px)
			result.enemy_budget_updates += int(trace.get("stopped_by_budget", false))
			result.enemy_contacts += trace.get("contacts", []).size()
			enemies.append(trace.duplicate(true))
		if frame == checkpoint:
			result["paired_before_intervention"] = _snapshot()
			_world(environment.world)
			if environment.enemies == 0:
				for actor: Enemy in _actors:
					actor.collision_layer = 0
			if environment.get("frozen", false):
				for actor: Enemy in _actors:
					actor.velocity = Vector2.ZERO
			# The intervention tick only: identical prefix, positions, and flipper plan.
		_step_context = _snapshot()
		var ball_overlaps_enemy := false
		for actor: Enemy in _actors:
			if actor.collision_layer != 0 and _main.ball.global_position.distance_to(actor.global_position) < _main.ball.radius + actor.radius:
				ball_overlaps_enemy = true
		result.pre_ball_overlap_updates += int(ball_overlaps_enemy)
		if ordinary:
			plans.clear()
		_main.ball.advance(1.0 / 60.0, plans)
		_collect_integration(result, _motion as Recorder)
		var recorder := _motion as CausalMotion
		var interesting: bool = _full_events or recorder.recovery.tick.get("overlapping", false)
		interesting = interesting or recorder.discarded_seconds > 0.0 or recorder.events.any(
			func(event: Dictionary) -> bool:
				return event.correction_px > 20.0 or not event.environment.get("introduced", []).is_empty())
		if interesting:
			var record := _result(recorder)
			record["frame"] = frame
			record["pre_ball"] = _step_context.duplicate(true)
			record["enemies"] = enemies
			result.important.append(record)
		if result.unresolved or frame == checkpoint:
			break
		if actual.get("routes", false):
			for actor: Enemy in _actors:
				if actor.active and _main.boundary.has_exited(actor.global_position, actor.radius):
					actor.finish(Enemy.ExitReason.ESCAPED)
		await physics_frame
	result["position"] = _vec(_main.ball.global_position)
	result["velocity"] = _vec(_main.ball.velocity)
	result["completed"] = not result.unresolved
	for actor: Enemy in _actors:
		if is_instance_valid(actor):
			actor.free()
	return result


func _obstacles(target: CharacterBody2D, radius: float, mask: int = 2) -> Array[Dictionary]:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, target.global_position)
	query.collision_mask = mask
	query.collide_with_areas = false
	query.exclude = [target.get_rid()]
	var output: Array[Dictionary] = []
	for hit: Dictionary in target.get_world_2d().direct_space_state.intersect_shape(query, 32):
		var actor := hit.collider as PhysicsBody2D
		var depth := 0.0
		if actor is PinballFlipper:
			depth = actor._contact_at(target.global_position, radius, actor.global_transform, 0.0, 0.0).get("depth", 0.0)
		elif actor is Enemy:
			depth = radius + actor.radius - target.global_position.distance_to(actor.global_position)
		elif actor is PinballBumper:
			depth = radius + actor.radius - target.global_position.distance_to(actor.global_position)
		else:
			var collision := actor.get_child(0) as CollisionShape2D
			var segments := collision.shape as ConcavePolygonShape2D
			if segments != null:
				var closest := INF
				for index: int in range(0, segments.segments.size(), 2):
					var point := Geometry2D.get_closest_point_to_segment(target.global_position,
						collision.to_global(segments.segments[index]), collision.to_global(segments.segments[index + 1]))
					closest = minf(closest, point.distance_to(target.global_position))
				depth = radius - closest
		output.append({"target": str(actor.name), "depth_px": maxf(0.0, depth),
			"kind": "flipper" if actor is PinballFlipper else ("enemy" if actor is Enemy else "world")})
	return output


func _write(filename: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://experiments/flippers/evidence/" + filename, FileAccess.WRITE)
	assert(file != null, "Cannot write evidence: " + filename + " (" + str(FileAccess.get_open_error()) + ")")
	file.store_string(JSON.stringify(value))


func _snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for actor: Enemy in _actors:
		if not is_instance_valid(actor):
			continue
		actors.append({"position": _vec(actor.global_position), "velocity": _vec(actor.velocity),
			"layer": actor.collision_layer, "mask": actor.collision_mask,
			"move": _vec(actor._movement_velocity), "knockback": _vec(actor._knockback_initial),
			"knockback_elapsed": actor._knockback_elapsed, "crowd": _vec(actor.crowd_motion),
			"health": actor.current_health, "radius": actor.radius})
	return {"ball_position": _vec(_main.ball.global_position), "ball_velocity": _vec(_main.ball.velocity),
		"guard": _main.flippers.is_target_disabled(_main.ball.get_instance_id()), "enemies": actors}


func _layers() -> Dictionary:
	var actor := _new_enemy(Vector2(960, 500))
	var result := {"ball_layer": _main.ball.collision_layer, "ball_mask": _main.ball.collision_mask,
		"enemy_layer": actor.collision_layer, "enemy_mask": actor.collision_mask,
		"flipper_layer": _main.flippers.items[0].collision_layer,
		"ball_ball": (_main.ball.collision_mask & _main.ball.collision_layer) != 0,
		"enemy_ball": (actor.collision_mask & _main.ball.collision_layer) != 0,
		"enemy_enemy": (actor.collision_mask & actor.collision_layer) != 0}
	actor.free()
	return result


func _enemy_conformance() -> Dictionary:
	_world("full")
	var actor := _new_enemy(Vector2(960, 500)) as CausalEnemy
	var cases := 0
	for start: Vector2 in [Vector2(960, 500), Vector2(650, 1000), Vector2(800, 1000), Vector2(960, 1080)]:
		for velocity: Vector2 in [Vector2.ZERO, Vector2(0, 600), Vector2(600, 0), Vector2(-600, 600)]:
			for crowd: Vector2 in [Vector2.ZERO, Vector2(7.5, 0), Vector2(0, -7.5)]:
				var outputs: Array[Dictionary] = []
				for observed: bool in [false, true]:
					actor.global_position = start
					actor.force_update_transform()
					actor._movement_velocity = velocity
					actor._knockback_initial = Vector2(180, -60)
					actor._knockback_elapsed = 0.03
					actor.crowd_motion = crowd
					actor.trace_enabled = observed
					actor.advance(1.0 / 60.0)
					outputs.append({"position": actor.global_position, "velocity": actor.velocity})
				_check((outputs[0].position as Vector2).distance_to(outputs[1].position) < 0.001,
					"Enemy observer changed displacement")
				_check((outputs[0].velocity as Vector2).distance_to(outputs[1].velocity) < 0.01,
					"Enemy observer changed velocity")
				cases += 1
	actor.free()
	return {"cases": cases}
