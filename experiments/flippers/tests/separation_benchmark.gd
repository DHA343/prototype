extends "res://experiments/flippers/tests/separation_audit.gd"

const LeanSeparation = preload("res://experiments/flippers/separation.gd")
const ROUNDS: int = 8


func _run() -> void:
	_read_inputs()
	var reference: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_response.json"))
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var fixtures: Array = previous.cases.duplicate()
	fixtures.append_array(detection.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	var hashes := _production_hashes()
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	for round_index: int in ROUNDS:
		var results := {}
		for offset: int in MATRIX.size():
			var config: Dictionary = MATRIX[(offset + round_index) % MATRIX.size()]
			_set_rule(int(config.rule))
			var times: Array[int] = []
			for index: int in fixtures.size():
				var saved: Dictionary = fixtures[index]
				var fixture := _fixture(saved)
				var source: PinballFlipper.Swing = fixture.source
				var held: bool = saved.case.angle == 0.0 if saved.has("case") else not _inputs[int(saved.id)].raised
				_main.flippers.pass_until_descending = true
				_main.flippers.advance(fixture.duration, held, held)
				var ball := _main.ball
				if config.separation:
					var candidate := LeanSeparation.new(ball)
					candidate.native_response = ball._resolve_contact
					ball._motion = candidate
				else:
					ball._motion = PinballMotion.new(ball)
					ball._motion.native_contact = ball._resolve_contact
				ball._motion.contact_recorded = ball._record_contact
				_motion = ball._motion
				ball.gravity = 0.0
				ball.collision_mask = (8 << source.flipper.side) if source != null else 8
				_reset_body({"radius": fixture.radius}, fixture.start, fixture.velocity)
				var plans: Array[PinballFlipper.Swing] = []
				if source != null:
					plans.append(source)
				var began := Time.get_ticks_usec()
				ball.advance(fixture.duration, plans)
				times.append(Time.get_ticks_usec() - began)
				if round_index == 0:
					var expected: Dictionary = reference.cases[index].methods[config.name]
					_check(ball.global_position.distance_to(_unvec(expected.position)) < 0.001,
						"Lean position differs from observed audit")
					_check(ball.velocity.distance_to(_unvec(expected.velocity)) < 0.01,
						"Lean velocity differs from observed audit")
					_check(ball.get_collision_exceptions().is_empty(), "Lean guard exclusions leaked")
			results[config.name] = times
		rounds.append({"warmup": round_index == 0, "times_us": results})
		print("Separation CPU round: ", round_index + 1, "/", ROUNDS)
		await process_frame
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("separation_benchmark.json", {"checks": _checks, "failures": _failures,
		"rounds": rounds, "production_sha256": hashes, "fixtures": fixtures.size(),
		"scope": "One warmup and seven measured rounds, rotated mode order; timed advance only. No trace or environment queries; candidate initial-contact queries included."})
	print("Separation CPU checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
