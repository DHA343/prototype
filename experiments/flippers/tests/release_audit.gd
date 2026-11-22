extends "res://experiments/flippers/tests/separation_audit.gd"

const ReleaseManager = preload("res://experiments/flippers/release_flippers.gd")
const ReleaseTrace = preload("res://experiments/flippers/tests/release_motion.gd")
const ReleaseRecovery = preload("res://experiments/flippers/release.gd")
const VARIANTS: Array[Dictionary] = [
	{"name": "production", "rule": 0, "separation": false, "budgets": false, "policy": 0, "limit": 3.0},
	{"name": "baseline", "rule": 2, "separation": true, "budgets": false, "policy": 0, "limit": 3.0},
	{"name": "postpone", "rule": 2, "separation": true, "budgets": false, "policy": 1, "limit": 3.0},
	{"name": "safe3", "rule": 2, "separation": true, "budgets": false, "policy": 2, "limit": 3.0},
	{"name": "safe6", "rule": 2, "separation": true, "budgets": false, "policy": 2, "limit": 6.0},
	{"name": "safe12", "rule": 2, "separation": true, "budgets": false, "policy": 2, "limit": 12.0},
]


func _run() -> void:
	_read_inputs()
	var hashes := _production_hashes()
	_config = VARIANTS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var contracts := await _contracts()
	var grid := _release_grid()
	_write("release_grid.json", {"cases": grid, "checks": _checks, "failures": _failures})
	var integration := {}
	for config: Dictionary in VARIANTS:
		_config = config
		_set_rule(int(config.rule))
		integration[config.name] = {"near_enemy": await _near_grid(), "population": await _population_grid()}
		print("Release integration: ", config.name)
	var transitions := _transition_grid()
	var tails := await _delay_tails()
	var regression := _unchanged_fixtures()
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("release_audit.json", {"checks": _checks, "failures": _failures, "variants": VARIANTS,
		"integration": integration, "transitions": transitions, "tails": tails,
		"contracts": contracts, "regression": regression, "production_sha256": hashes})
	print("Release checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _make_main(_counted: bool) -> void:
	_main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(_main, 0)
	ReleaseManager.install(_main)
	_main.get_node("EnemySpawner").enabled = false
	root.add_child(_main)
	_main.set_physics_process(false)
	_main.get_node("Playfield/ShotGuide").set_physics_process(false)
	_main.ball.max_speed = 3600.0
	_main.ball.hit_sound = null
	for item: PinballFlipper in _main.flippers.items:
		item.collision_layer = 8 << item.side
	_attach_recorder(_main.ball)
	_motion = _main.ball._motion


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := ReleaseTrace.new(ball)
	recorder.normal_for_new_contact = _config.separation
	recorder.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	recorder.recovery.limit = _config.limit
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _result(recorder: Trace, cpu: int = 0) -> Dictionary:
	var result := super._result(recorder, cpu)
	var recovery: ReleaseRecovery = (recorder as ReleaseTrace).recovery
	result["release"] = recovery.tick.duplicate(true)
	result["release_requested"] = recovery.tick.get("requested", false)
	result.guard_released = recovery.tick.get("released", false)
	result["unresolved"] = recovery.failed
	result["pending_ms"] = (recovery._waiting + recovery._duration) * 1000.0 if recovery._pending else 0.0
	result["guard_active"] = _main.flippers.is_target_disabled(recorder.body.get_instance_id())
	var correction := Vector2.ZERO
	if not recovery.tick.is_empty():
		correction = _unvec(recovery.tick.correction)
	result["release_correction_px"] = correction.length()
	result.max_correction_px = maxf(result.max_correction_px, correction.length())
	return result


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	var observed := _result(recorder as Trace)
	result.max_correction_px = maxf(result.max_correction_px, observed.max_correction_px)
	if not observed.release.is_empty():
		if not result.has("release_events"):
			result["release_events"] = []
		observed["update_index"] = result.updates - 1
		observed["ball_id"] = str(recorder.body.get_instance_id())
		result.release_events.append(observed)
	result["max_delay_ms"] = maxf(result.get("max_delay_ms", 0.0),
		maxf(observed.pending_ms, observed.release.get("delay_ms", 0.0)))
	result["unresolved"] = result.get("unresolved", false) or observed.unresolved
	result["guard_active_at_end"] = observed.guard_active
	if observed.release.get("deferred", false):
		var before := _unvec(observed.release.before)
		if _crossed_bottom(before, recorder.body.global_position, recorder.radius):
			result["below_overdue"] = result.get("below_overdue", 0) + 1
	_check(recorder.body.get_collision_exceptions().is_empty(), "Guard exceptions leaked")
	_check(not observed.unresolved or recorder.events.is_empty(), "Failed safe recovery still moved")


func _new_result(extra: Dictionary) -> Dictionary:
	var result := {"shots": 0, "contacts": 0, "exhausted_updates": 0, "discarded_ms": 0.0,
		"max_correction_px": 0.0, "below_overdue": 0, "unresolved": false}
	result.merge(extra)
	return result


func _release_fixture(input: Dictionary, moving: bool, rate: float, config: Dictionary) -> Dictionary:
	_config = config
	_set_rule(int(config.rule))
	_set_pose(input.angle)
	var item := _main.flippers.items[int(input.side)] as TableFlipper
	var plans: Array[PinballFlipper.Swing] = []
	if moving:
		plans.append(item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0))
		_main.flippers.advance(1.0 / rate, input.angle == 0.0, input.angle == 0.0)
	_attach_recorder(_main.ball)
	_motion = _main.ball._motion
	_main.flippers.pass_until_descending = true
	_main.ball.gravity = 1500.0
	_main.ball.collision_mask = 8 << int(input.side)
	_reset_body(input, _unvec(input.start), Vector2(0, -1))
	_main.flippers.disable_target(_main.ball)
	_main.ball.advance(1.0 / rate, plans)
	return _result(_motion as Trace)


func _release_grid() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for input: Dictionary in _static_cases(true):
		for moving: bool in [false, true]:
			for rate: float in [30.0, 60.0, 120.0]:
				var methods := {}
				for config: Dictionary in VARIANTS:
					methods[config.name] = _release_fixture(input, moving, rate, config)
				rows.append({"case": input, "moving": moving, "rate": rate, "methods": methods})
	print("Release grid: ", rows.size())
	return rows


func _near_grid() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for ratio: float in [0.05, 0.15, 0.30, 0.50, 0.70, 0.90, 0.99]:
		for gap: float in [3, 12, 36, 72]:
			for offset: float in [-36, 0, 36]:
				_reset_integration()
				var polygon := (_main.flippers.items[0] as TableFlipper).world_polygon_at(
					_main.flippers.items[0].global_transform)
				_main.ball.reset_at(polygon[0].lerp(polygon[1], ratio) + Vector2.UP * 28, Vector2(0, 300))
				var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
				enemy.death_cue = null
				enemy.position = _main.ball.global_position + Vector2(offset, -(54.0 + gap))
				_main.get_node("Playfield").add_child(enemy)
				enemy.prepare(enemy.grow_duration)
				await physics_frame
				var result := _new_result({"ratio": ratio, "gap": gap, "offset": offset})
				for frame: int in 60:
					var plans := _main.flippers.plan_motion(true, true)
					_main.flippers.advance(1.0 / 60.0, true, true)
					if is_instance_valid(enemy):
						enemy.prepare(1.0 / 60.0)
						enemy.advance(1.0 / 60.0)
					_main.ball.advance(1.0 / 60.0, plans)
					_collect_integration(result, _motion as Recorder)
					if result.unresolved:
						break
					await physics_frame
				result["completed"] = not result.unresolved
				result["position"] = _vec(_main.ball.global_position)
				if is_instance_valid(enemy):
					enemy.free()
				rows.append(result)
	return rows


func _population_grid() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for count: int in [1, 20]:
		_reset_integration()
		var balls: Array[PinballBall] = [_main.ball]
		for index: int in range(1, count):
			var ball := PinballBall.new()
			var collision := CollisionShape2D.new()
			collision.name = "CollisionShape2D"
			collision.shape = CircleShape2D.new()
			ball.add_child(collision)
			_main.get_node("Playfield").add_child(ball)
			ball.boundary = _main.boundary
			ball.flippers = _main.flippers
			_attach_recorder(ball)
			balls.append(ball)
		for index: int in count:
			var random := RandomNumberGenerator.new()
			random.seed = 11000 + index
			var ball := balls[index]
			ball.radius = 24.0
			ball.gravity = 1500.0
			ball.max_speed = 3600.0
			ball.hit_sound = null
			ball.collision_mask = 6
			var start := Vector2.ZERO
			for attempt: int in 64:
				start = Vector2(random.randf_range(610, 1310), random.randf_range(180, 760))
				var query := PhysicsShapeQueryParameters2D.new()
				var circle := CircleShape2D.new()
				circle.radius = 24.1
				query.shape = circle
				query.transform = Transform2D(0.0, start)
				query.collision_mask = 6
				if ball.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
					break
			ball.reset_at(start, Vector2(random.randf_range(-400, 400), random.randf_range(0, 500)))
		await physics_frame
		var result := _new_result({"balls": count, "exited": 0})
		for frame: int in 360:
			var left := fmod(frame / 60.0, 0.55) < 0.08
			var right := fmod(frame / 60.0 + 0.275, 0.55) < 0.08
			var plans := _main.flippers.plan_motion(left, right)
			_main.flippers.advance(1.0 / 60.0, left, right)
			for ball: PinballBall in balls:
				if not ball.active:
					continue
				ball.advance(1.0 / 60.0, plans)
				_collect_integration(result, ball._motion as Recorder)
				if result.unresolved:
					break
				if _main.boundary.to_local(ball.global_position).y > _main.boundary.bottom + 120.0:
					ball.active = false
					ball._motion.reset()
					result.exited += 1
			if result.unresolved:
				break
			await physics_frame
		result["completed"] = not result.unresolved
		for ball: PinballBall in balls:
			if ball != _main.ball:
				ball.free()
		rows.append(result)
	return rows


func _transition_grid() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for config: Dictionary in VARIANTS:
		_config = config
		_set_rule(int(config.rule))
		for kind: String in ["release_rest", "release_held", "release_rising", "stop_now", "stop_next"]:
			_reset_integration()
			var item := _main.flippers.items[0] as TableFlipper
			if kind.begins_with("release"):
				if kind == "release_held":
					_main.flippers.advance(18.0 / 600.0, true, false)
				var points := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(points[0].lerp(points[1], 0.65) + Vector2.DOWN * 12, Vector2(0, -1))
				_main.flippers.disable_target(_main.ball)
			else:
				_main.flippers.advance(15.0 / 600.0, true, false)
				var points := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(points[0].lerp(points[1], 0.65) + Vector2.UP * 28, Vector2(0, 600))
				if kind == "stop_next":
					_main.flippers.advance(3.0 / 600.0, true, false)
			var pressed := kind != "release_rest"
			var plans := _main.flippers.plan_motion(pressed, false)
			_main.flippers.advance(1.0 / 60.0, pressed, false)
			_main.ball.advance(1.0 / 60.0, plans)
			rows.append({"mode": config.name, "case": kind, "result": _result(_motion as Trace)})
	return rows


func _delay_tails() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for config: Dictionary in VARIANTS:
		_config = config
		_set_rule(int(config.rule))
		for kind: String in ["slow_inside", "stationary_inside", "other_flipper"]:
			_reset_integration()
			var ball := _main.ball
			ball.gravity = 0.0
			ball.max_speed = 3600.0
			ball.collision_mask = 24
			for flipper: PinballFlipper in _main.flippers.items:
				flipper.collision_layer = 8 << flipper.side
			var item := _main.flippers.items[0] as TableFlipper
			var points := item.world_polygon_at(item.global_transform)
			var start := points[0].lerp(points[1], 0.65) + Vector2.DOWN * 12
			ball.reset_at(start, Vector2(0, 2))
			if kind == "other_flipper":
				ball.reset_at(Vector2(item.fixed_right + 1, item.fixed_bottom - 24), Vector2(3600, 2))
			_main.flippers.disable_target(ball)
			var initial := (_motion as ReleaseTrace).recovery
			initial.begin(ball, ball.radius, _main.flippers, [], 1.0 / 60.0)
			_check(not initial.contacts(ball.global_position).is_empty(), "Tail must start inside a flipper")
			var result := _new_result({"case": kind})
			var previous_right := false
			for frame: int in 120:
				if kind == "stationary_inside" and frame > 0:
					ball.velocity = Vector2.ZERO
				var before_right := not (_motion as ReleaseTrace).recovery.contacts(ball.global_position).filter(
					func(hit: Dictionary) -> bool: return hit.flipper.side == 1).is_empty() if frame > 0 else false
				ball.advance(1.0 / 60.0)
				_collect_integration(result, _motion as Recorder)
				var right := not (_motion as ReleaseTrace).recovery.contacts(ball.global_position).filter(
					func(hit: Dictionary) -> bool: return hit.flipper.side == 1).is_empty()
				if right and not before_right and not previous_right and result.guard_active_at_end:
					result["right_entry_while_disabled"] = result.get("right_entry_while_disabled", 0) + 1
				previous_right = right
				if result.unresolved:
					break
				await physics_frame
			result["position"] = _vec(ball.global_position)
			result["completed"] = not result.unresolved
			rows.append({"mode": config.name, "result": result})
	return rows


func _unchanged_fixtures() -> Dictionary:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var extras: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_response.json"))
	var fixtures: Array = previous.cases.duplicate()
	fixtures.append_array(extras.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	for index: int in fixtures.size():
		for config: Dictionary in VARIANTS:
			var result := _policy_replay(fixtures[index], config)
			var expected: Dictionary = golden.cases[index].methods.current if config.name == "production" else golden.cases[index].methods.combined
			_check(_unvec(result.position).distance_to(_unvec(expected.position)) < 0.001, "Unguarded position changed")
			_check(_unvec(result.velocity).distance_to(_unvec(expected.velocity)) < 0.01, "Unguarded velocity changed")
	print("Release unguarded regression: ", fixtures.size())
	return {"cases": fixtures.size(), "variants": VARIANTS.size()}


func _contracts() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_config = VARIANTS[3]
	_set_pose(0.0)
	_main.ball.collision_mask = 2
	var wall := StaticBody2D.new()
	wall.collision_layer = 2
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1, 80)
	shape.shape = rectangle
	wall.add_child(shape)
	_main.get_node("Playfield").add_child(wall)
	wall.global_position = Vector2(960, 850)
	wall.force_update_transform()
	await physics_frame
	var recovery := ReleaseRecovery.new()
	recovery.begin(_main.ball, 6.0, _main.flippers, [], 1.0 / 60.0)
	for fixture: Dictionary in [
		{"name": "cross_wall", "start": Vector2(930, 850), "offset": Vector2(60, 0), "expected": "world_path"},
		{"name": "endpoint_wall", "start": Vector2(930, 850), "offset": Vector2(25, 0), "expected": "world_endpoint"},
		{"name": "exit_existing", "start": Vector2(953.9, 850), "offset": Vector2(-10, 0), "expected": ""},
		{"name": "traverse_existing", "start": Vector2(953.9, 850), "offset": Vector2(20, 0), "expected": "deeper_into_world"},
	]:
		_main.ball.global_position = fixture.start
		_main.ball.force_update_transform()
		var reason := recovery.world_safety(fixture.offset, [])
		_check(reason == fixture.expected, "Correction safety classification failed: " + fixture.name + ": " + reason)
		_check(_main.ball.global_position == fixture.start, "Safety query moved the ball")
		rows.append({"case": fixture.name, "reason": reason})
	wall.free()
	for input: Dictionary in _static_cases(true):
		if input.angle != 0 or input.side != 0 or input.radius != 6 or input.feature != 0:
			continue
		_set_pose(0.0)
		_attach_recorder(_main.ball)
		_motion = _main.ball._motion
		_main.ball.collision_mask = 8
		_main.flippers.pass_until_descending = true
		_reset_body(input, _unvec(input.start), Vector2(0, 2))
		_main.flippers.disable_target(_main.ball)
		recovery = (_motion as ReleaseTrace).recovery
		recovery.begin(_main.ball, 6.0, _main.flippers, [], 1.0 / 60.0)
		var velocity := _main.ball.velocity
		var start := _main.ball.global_position
		recovery.refresh(2.0)
		_check(_main.ball.velocity == velocity, "Release correction changed velocity")
		if recovery.failed:
			_check(_main.ball.global_position == start, "Failed correction moved the ball")
			_check(_main.flippers.is_target_disabled(_main.ball.get_instance_id()), "Failed correction released guard")
		else:
			_check(_main.ball.global_position.distance_to(start) <= 3.0, "Safe correction exceeded limit")
			_check(recovery.contacts(_main.ball.global_position, 0.03).is_empty(), "Safe correction left flipper overlap")
		rows.append({"case": "direct_release", "input": input, "release": recovery.tick})
	_main.flippers.reset_input()
	return rows
