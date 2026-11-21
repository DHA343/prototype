extends "res://experiments/flippers/tests/refinement_audit.gd"


func _run() -> void:
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for saved: Dictionary in detection.cases:
		if saved.suite != "moving_edges":
			continue
		var outputs := {}
		var input: Dictionary = saved.case
		for mode: int in [-2, 0, 2, 4, 8, -1]:
			_mode = maxi(mode, -1)
			var fixture := _fixture(saved)
			var source: PinballFlipper.Swing = fixture.source
			var hit := {}
			if mode == -2 and saved.reference.found:
				var time: float = saved.reference.time_ms / 1000.0
				hit = source.flipper._contact_at(fixture.start + fixture.velocity * time,
					fixture.radius + 0.0005, _pose(source.flipper, source,
						source.flipper.global_transform, time),
					source.speed if time < source.stop_time else 0.0, _main.flippers.power_equalization)
				_check(not hit.is_empty(), "Saved reference contact could not be represented")
				hit["time"] = time
				hit["flipper"] = source.flipper
			_main.ball.collision_mask = 8 << int(input.side)
			_main.flippers.pass_until_descending = mode != -2
			_main.flippers.advance(fixture.duration, input.angle == 0.0, input.angle == 0.0)
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_reset_body(input, fixture.start, fixture.velocity)
			var recorder := _motion as Recorder
			if mode == -2:
				recorder.begin(fixture.duration)
				if not hit.is_empty():
					recorder.apply_swept_contact(hit)
			else:
				_main.ball.advance(fixture.duration, [source])
			var result := _response(recorder, fixture.duration, input)
			outputs["reference" if mode == -2 else _label(mode)] = result
			_check(_main.ball.get_collision_exceptions().is_empty(), "Edge response exclusions leaked")
		rows.append({"id": saved.id, "rate": saved.rate, "case": input,
			"ambiguous": saved.ambiguous, "reference": outputs.reference.first,
			"methods": {"B": outputs.B, "B+2": outputs["B+2"], "B+4": outputs["B+4"],
				"B+8": outputs["B+8"], "D2": outputs.D2}})
	_main.free()
	_write("refinement_edges_response.json", {"checks": _checks, "failures": _failures,
		"cases": rows, "scope": "2016 moving edge fixtures; reference is first response only; candidates run a full tick with guard 3"})
	print("Refinement edge response checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
