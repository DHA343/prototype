extends SceneTree

const Preview = preload("res://experiments/flippers/separation_preview.gd")
const Audit = preload("res://experiments/flippers/tests/guard_audit.gd")
const Trace = preload("res://experiments/flippers/tests/guard_trace.gd")

var _preview: Preview
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var episodes: Array = []
	for episode_seed: int in [113, 271]:
		var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://experiments/flippers/evidence/guard_current_" + str(episode_seed) + ".json"))
		for episode: Dictionary in saved.guard_episodes:
			episode["source_seed"] = episode_seed
			episodes.append(episode)
	var cases: Array[Dictionary] = []
	for age: int in [1, 2]:
		var matched := episodes.filter(func(row: Dictionary) -> bool:
			return row.internal and int(row.release_frame) - int(row.shot_frame) == age)
		if matched.is_empty():
			push_error("No saved live episode of requested age")
			quit(1)
			return
		var episode: Dictionary = matched[0]
		cases.append({"kind": "recorded", "name": "live_age" + str(age), "recorded": episode.rows[0].before_ball,
			"source_frame": episode.shot_frame, "source_seed": episode.source_seed, "ticks": 6,
			"expected_after_first": {"position": episode.rows[0].position_after,
				"velocity": episode.rows[0].velocity_after}})
	for ratio: float in [.05, .5, .99]:
		cases.append({"kind": "normal", "name": "top_" + str(ratio), "ratio": ratio, "ticks": 18})
	for ratio: float in [.92, .99]:
		cases.append({"kind": "async", "name": "opposite_raised_" + str(ratio), "ratio": ratio, "ticks": 18})
	for variant: int in 3:
		cases.append({"kind": "near", "name": "near_" + str(variant), "variant": variant, "ticks": 30})
	cases.append({"kind": "descending", "name": "descending_catch", "ticks": 2})
	cases.append({"kind": "pass", "name": "guarded_opposite_underpass", "ticks": 4})
	cases.append({"kind": "continuous", "name": "continuous_3s", "ratio": .5, "ticks": 180})
	_preview = load("res://experiments/flippers/separation_preview.tscn").instantiate() as Preview
	root.add_child(_preview)
	while _preview.loading: await physics_frame
	var rows: Array[Dictionary] = []
	for fixture: Dictionary in cases:
		var starts: Array = []
		for method: String in ["current", "early", "immediate"]:
			await _prepare(fixture, method)
			starts.append(_preview.scenes.snapshot(_preview.main))
			var trace := _preview.main.ball._motion as Trace
			var steps: Array[Dictionary] = []
			for frame: int in int(fixture.ticks):
				trace.clock_frame = frame
				_step(fixture, frame)
				steps.append(trace.tick.duplicate(true))
				_check(_preview.main.ball.get_collision_exceptions().is_empty(), "Guard exceptions leaked")
				await physics_frame
			rows.append({"fixture": fixture, "method": method, "initial": starts.back(), "steps": steps})
		_check(starts[0] == starts[1] and starts[0] == starts[2], "Guard comparison starts differ")
		print("Guard local: ", fixture.name)
	_preview.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/guard_cases.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "cases": rows,
		"recorded_scope": "First pre-ball state restored. Later Enemy movement commands held; route/crowd history not restored"}))
	print("Guard local checks: ", _checks, "; failures: ", _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _prepare(fixture: Dictionary, method: String) -> void:
	_preview.variant = int(fixture.get("variant", 0)) % 2
	await _preview.reset_case(3 if fixture.kind == "near" else 7, 1)
	var main := _preview.main
	Audit.install_manager(main, method == "early")
	var trace := Trace.new(main.ball)
	trace.same_tick_descent = method == "immediate"
	trace.native_response = main.ball._resolve_contact
	trace.contact_recorded = main.ball._record_contact
	main.ball._motion = trace
	var left := main.flippers.items[0] as TableFlipper
	if fixture.kind == "recorded":
		var state: Dictionary = fixture.recorded
		main.flippers.reset_input()
		for side: int in 2:
			main.flippers.items[side].advance(absf(state.offsets[side]) / deg_to_rad(600), true, 18, 600, 420)
		main.ball.reset_at(_vec(state.position), _vec(state.velocity))
		if state.guard: main.flippers.disable_target(main.ball)
		for saved: Dictionary in state.enemies:
			var actor := _preview.scenes._add_enemy(main, _vec(saved.position))
			actor.radius = saved.radius
			actor.velocity = _vec(saved.velocity)
			actor._movement_velocity = _vec(saved.movement)
			actor._knockback_initial = _vec(saved.knockback)
			actor._knockback_elapsed = saved.knockback_elapsed
			actor.crowd_motion = _vec(saved.crowd)
			actor.current_health = saved.health
			actor._spawn_elapsed = saved.spawn_elapsed
			actor.collision_layer = saved.layer
			if saved.get("ball_contact_blocked", false): main.ball._enemy_contacts.append(actor)
	elif fixture.kind in ["normal", "async", "continuous"]:
		if fixture.kind == "async": main.flippers.items[1].advance(.03, true, 18, 600, 420)
		var points := left.world_polygon_at(left.global_transform)
		main.ball.reset_at(points[0].lerp(points[1], fixture.ratio) + Vector2.UP * 28, Vector2(0, 300))
	elif fixture.kind == "near" and fixture.variant == 2:
		var points := left.world_polygon_at(left.global_transform)
		main.ball.reset_at(points[0].lerp(points[1], .9) + Vector2.UP * 28, Vector2(0, 300))
		_preview.scenes.actors[0].global_position = main.ball.global_position + Vector2(0, -57)
		_preview.scenes.actors[0].force_update_transform()
	elif fixture.kind == "descending":
		var right := main.flippers.items[1] as TableFlipper
		var points := right.world_polygon_at(right.global_transform)
		main.ball.reset_at(points[0].lerp(points[1], .4) + Vector2.UP * 28, Vector2(0, 500))
		main.flippers.disable_target(main.ball)
	elif fixture.kind == "pass":
		var right := main.flippers.items[1] as TableFlipper
		main.ball.reset_at(Vector2(lerpf(right.fixed_left, right.fixed_right, .25),
			right.fixed_bottom + main.ball.radius + 2), Vector2(0, -1800))
		main.flippers.disable_target(main.ball)
	await physics_frame


func _step(fixture: Dictionary, frame: int) -> void:
	var main := _preview.main
	var held: bool = fixture.kind != "descending"
	if fixture.kind == "continuous": held = fmod(float(frame) / 60, .5) < .12
	var plans := main.flippers.plan_motion(held, held)
	main.flippers.advance(1.0 / 60.0, held, held)
	if not (fixture.kind == "recorded" and frame == 0):
		for actor: Enemy in _preview.scenes.actors:
			if not is_instance_valid(actor) or not actor.active: continue
			if fixture.kind != "recorded": actor.prepare(1.0 / 60.0)
			actor.advance(1.0 / 60.0)
	main.ball.advance(1.0 / 60.0, plans)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
