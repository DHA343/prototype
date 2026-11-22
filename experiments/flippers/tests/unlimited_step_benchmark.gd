extends "res://experiments/flippers/tests/unlimited_audit.gd"

const LeanRelease = preload("res://experiments/flippers/release_motion.gd")


func _attach_recorder(ball: PinballBall) -> void:
	var candidate := LeanRelease.new(ball)
	candidate.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	candidate.recovery.limit = _config.limit
	candidate.recovery.distance_limited = not _config.get("unlimited", false)
	candidate.recovery.diagnostics = false
	candidate.native_response = ball._resolve_contact
	candidate.contact_recorded = ball._record_contact
	ball._motion = candidate


func _run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/unlimited_grid.json"))
	var common: Array[int] = []
	for index: int in golden.cases.size():
		if not golden.cases[index].methods.safe12.unresolved:
			common.append(index)
	var hashes := _production_hashes()
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	for round_index: int in 8:
		var methods := {}
		for offset: int in 3:
			var config: Dictionary = TRIALS[(offset + round_index) % 3]
			_config = config
			_set_rule(2)
			var rows: Array[Dictionary] = []
			for index: int in golden.cases.size():
				if config.name == "safe12" and not common.has(index):
					continue
				var row: Dictionary = golden.cases[index]
				var input: Dictionary = row.case
				_set_pose(input.angle)
				var plans: Array[PinballFlipper.Swing] = []
				if row.moving:
					var item: PinballFlipper = _main.flippers.items[int(input.side)]
					plans.append(item.plan_motion(input.angle == 0.0, 18.0,
						600.0 if input.angle == 0.0 else 420.0))
					_main.flippers.advance(1.0 / row.rate, input.angle == 0.0, input.angle == 0.0)
				_attach_recorder(_main.ball)
				_motion = _main.ball._motion
				_main.flippers.pass_until_descending = true
				_main.ball.gravity = 1500.0
				_main.ball.collision_mask = 8 << int(input.side)
				_reset_body(input, _unvec(input.start), Vector2(0, -1))
				_main.flippers.disable_target(_main.ball)
				var began := Time.get_ticks_usec()
				_main.ball.advance(1.0 / row.rate, plans)
				var elapsed := Time.get_ticks_usec() - began
				_check(not (_motion as LeanRelease).recovery.failed, "Step CPU trial aborted")
				if round_index == 0:
					var expected: Dictionary = row.methods[config.name]
					_check(_main.ball.global_position.distance_to(_unvec(expected.position)) < 0.001,
						"Step CPU position differs")
					_check(_main.ball.velocity.distance_to(_unvec(expected.velocity)) < 0.01,
						"Step CPU velocity differs")
					_check(_main.ball.get_collision_exceptions().is_empty(), "Step CPU exclusions leaked")
				rows.append({"index": index, "us": elapsed})
			methods[config.name] = rows
		rounds.append({"warmup": round_index == 0, "methods": methods})
		print("Unlimited step CPU round: ", round_index + 1, "/8")
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("unlimited_step_benchmark.json", {"checks": _checks, "failures": _failures,
		"rounds": rounds, "common_indices": common, "production_sha256": hashes,
		"scope": "Identical-state single-update microbenchmark; all measured inputs complete. Three-way shared shallow inputs and baseline/unlimited all inputs are separate cohorts. No game-frame/FPS inference."})
	print("Unlimited step CPU checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
