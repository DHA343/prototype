extends "res://experiments/flippers/tests/matrix_enemy_test.gd"

const ContactBall = preload("res://experiments/flippers/tests/contact_ball.gd")


func _run() -> void:
	_preview = _make_preview(ContactBall)
	await physics_frame
	await physics_frame
	var near: Array[Dictionary] = []
	for run in 4:
		var limit: int = [2, 4, 8, 8][run]
		(_preview.ball as ContactBall).contact_limit = limit
		for ratio: float in [0.05, 0.15, 0.30, 0.50, 0.70, 0.90, 0.99]:
			for gap: float in [3, 12, 36, 72]:
				for offset: float in [-36, 0, 36]:
					(_preview.ball as ContactBall).reset_audit()
					var result: Dictionary = await _enemy_case("no_split_iterative", ratio, gap, offset)
					var ball := _preview.ball as ContactBall
					result.merge({"limit": limit, "run": run, "exhausted_updates": ball.exhausted_updates,
						"discarded_ms": ball.discarded_seconds * 1000,
						"exhausted_traces": ball.exhausted_traces.duplicate(true),
						"zero_time_contacts": ball.zero_time_contacts,
						"no_progress_contacts": ball.no_progress_contacts,
						"end": [ball.global_position.x, ball.global_position.y],
						"velocity": [ball.velocity.x, ball.velocity.y]})
					near.append(result)
	var population: Array[Dictionary] = []
	_preview.set_ball_count(20)
	for run in 4:
		var limit: int = [2, 4, 8, 8][run]
		for target: ContactBall in _preview.balls:
			target.contact_limit = limit
			target.reset_audit()
		await _response_case(48, false, true, 2, true)
		var result: Dictionary = _response_results.back().duplicate()
		result["limit"] = limit
		result["run"] = run
		result["exhausted_updates"] = 0
		result["discarded_ms"] = 0.0
		result["zero_time_contacts"] = 0
		result["ends"] = []
		for target: ContactBall in _preview.balls:
			result.exhausted_updates += target.exhausted_updates
			result.discarded_ms += target.discarded_seconds * 1000
			result.zero_time_contacts += target.zero_time_contacts
			result.ends.append([target.global_position.x, target.global_position.y,
				target.velocity.x, target.velocity.y])
		population.append(result)
	var file := FileAccess.open("res://experiments/flippers/evidence/contact_limits.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"near_enemy": near, "population": population,
		"checks": checks, "failures": failures,
		"scope": "no global subdivision; existing intermediate-pose sampling; guard 3; only contact cap changes"}, "\t"))
	print("Contact limits checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)
