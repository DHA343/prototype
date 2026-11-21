extends "res://experiments/flippers/tests/independent_audit.gd"

const World = preload("res://experiments/flippers/tests/load_world.gd")
const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var native: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var fixtures: Array = native.cases.filter(func(row: Dictionary) -> bool:
		return row.suite == "main_336" and row.rate == 60)
	var known: Array = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/refinement_audit_summary.json")).known_17
	for row: Dictionary in detection.cases:
		if row.suite == "moving_edges" and known.any(func(saved: Dictionary) -> bool:
			return saved.id == row.id and saved.rate == row.rate):
			fixtures.append(row)
	_check(fixtures.size() == 353, "Snapshot fixture count changed")
	var results: Array[Dictionary] = []
	for count: int in [0, 10, 30, 60]:
		var world := World.new()
		root.add_child(world)
		world.setup({"balls": 1, "enemies": count, "moving": true}, false, false)
		_main = world.main
		for attempt in 300:
			await physics_frame
			if not _main.routes.path_from(Vector2(800, 200), 30.0).is_empty():
				break
		world.settle_balls()
		await physics_frame
		_check(world.populate(), "Snapshot enemies could not be placed")
		await physics_frame
		for run in 8:
			for fixture: Dictionary in fixtures:
				for mode: int in ([0, 4] if run % 2 == 0 else [4, 0]):
					var source: PinballFlipper.Swing
					var input: Dictionary
					if fixture.suite == "moving_edges":
						input = fixture.case
						_set_pose(input.angle)
						var item := _main.flippers.items[int(input.side)] as TableFlipper
						source = item.plan_motion(input.angle == 0.0, 18.0, 600.0)
					else:
						input = _inputs[int(fixture.id)]
						source = _prepare(input)
					var duration: float = 1.0 / fixture.rate
					var held: bool = input.angle == 0.0 if fixture.suite == "moving_edges" else not input.raised
					_main.flippers.pass_until_descending = true
					_main.flippers.advance(duration, held, held)
					_main.ball.gravity = 0.0
					_main.ball.collision_mask = 6 | (8 << source.flipper.side) if source != null else 14
					_main.ball._motion = PinballMotion.new(_main.ball) if mode == 0 else RefinedMotion.new(_main.ball)
					_motion = _main.ball._motion
					_motion.native_contact = _main.ball._resolve_contact
					_motion.contact_recorded = _main.ball._record_contact
					_reset_body(input, _unvec(input.start), _unvec(input.velocity).limit_length(3600.0))
					for enemy: Enemy in _main.enemies:
						enemy.current_health = enemy.max_health
						enemy._knockback_initial = Vector2.ZERO
						enemy._knockback_elapsed = 0.0
						enemy.velocity = Vector2.ZERO
					_main.launcher._pending_shots.clear()
					var plans: Array[PinballFlipper.Swing] = []
					if source != null:
						plans.append(source)
					var began := Time.get_ticks_usec()
					_main.ball.advance(duration, plans)
					var elapsed := Time.get_ticks_usec() - began
					_check(_main.enemies.size() == count, "Snapshot changed the enemy population")
					_check(_main.ball.get_collision_exceptions().is_empty(), "Snapshot exclusions leaked")
					if run > 0:
						results.append({"enemies": count, "run": run, "mode": mode,
							"suite": fixture.suite, "id": fixture.id, "rate": fixture.rate,
							"ball_update_us": elapsed,
							"position": _vec(_main.ball.global_position), "velocity": _vec(_main.ball.velocity)})
		world.free()
		print("Load snapshot: ", count, " enemies; results=", results.size())
	var file := FileAccess.open("res://experiments/flippers/evidence/load_snapshot.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "checks": _checks, "failures": _failures,
		"automatic_updates_disabled": true,
		"scope": "353 identical-state ball updates: current 336 at 60Hz plus known 17; frozen real enemy bodies 0/10/30/60; no response recording; seven rounds after one warmup"}, "\t"))
	quit(0 if _failures == 0 else 1)
