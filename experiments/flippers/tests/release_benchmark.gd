extends "res://experiments/flippers/tests/release_audit.gd"

const LeanRelease = preload("res://experiments/flippers/release_motion.gd")


func _attach_recorder(ball: PinballBall) -> void:
	var candidate := LeanRelease.new(ball)
	candidate.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	candidate.recovery.limit = _config.limit
	candidate.recovery.diagnostics = false
	candidate.native_response = ball._resolve_contact
	candidate.contact_recorded = ball._record_contact
	ball._motion = candidate


func _run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/release_grid.json"))
	var hashes := _production_hashes()
	_config = VARIANTS[1]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	for round_index: int in 8:
		var output := {}
		for offset: int in 5:
			var config: Dictionary = VARIANTS[1 + (offset + round_index) % 5]
			_config = config
			_set_rule(2)
			var times: Array[int] = []
			for row: Dictionary in golden.cases:
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
				times.append(Time.get_ticks_usec() - began)
				if round_index == 0:
					var expected: Dictionary = row.methods[config.name]
					_check(_main.ball.global_position.distance_to(_unvec(expected.position)) < 0.001,
						"Lean recovery position differs")
					_check(_main.ball.velocity.distance_to(_unvec(expected.velocity)) < 0.01,
						"Lean recovery velocity differs")
					_check((_motion as LeanRelease).recovery.failed == expected.unresolved,
						"Lean recovery feasibility differs")
					_check(_main.ball.get_collision_exceptions().is_empty(), "Lean guard exceptions leaked")
			output[config.name] = times
		rounds.append({"warmup": round_index == 0, "times_us": output})
		print("Release CPU round: ", round_index + 1, "/8")
		await process_frame
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("release_benchmark.json", {"checks": _checks, "failures": _failures, "rounds": rounds,
		"fixtures": golden.cases.size(), "production_sha256": hashes,
		"scope": "Timed full ball.advance on release grid. No event history, before/after world observation, or candidate logs. Required safety queries included; failed trials remain separate."})
	print("Release CPU checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
