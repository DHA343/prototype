extends "res://experiments/flippers/tests/stable_audit.gd"


func _run() -> void:
	_read_inputs()
	_config = METHODS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_response.json"))
	var overlap_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_diagnostics.json"))
	var release_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/release_grid.json"))
	var fixtures: Array = saved.cases.duplicate()
	fixtures.append_array(extra.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	var hashes := _production_hashes()
	for config: Dictionary in [METHODS[0], METHODS[4], METHODS[5], METHODS[8], METHODS[9], METHODS[10], METHODS[11], METHODS[12], METHODS[13]]:
		if "--finish" in OS.get_cmdline_user_args() and not config.get("finish", false):
			continue
		if "--segmented" in OS.get_cmdline_user_args() and not config.get("segmented", false):
			continue
		var method := config.duplicate()
		method.rule = 2
		method.separation = true
		method.budgets = false
		var rows: Array[Dictionary] = []
		for index: int in fixtures.size():
			var result := _policy_replay(fixtures[index], method)
			if method.name == "baseline":
				var expected: Dictionary = golden.cases[index].methods.combined
				_check(_unvec(result.position).distance_to(_unvec(expected.position)) < 0.001,
					"Stability baseline position changed")
				_check(_unvec(result.velocity).distance_to(_unvec(expected.velocity)) < 0.01,
					"Stability baseline velocity changed")
			rows.append({"id": fixtures[index].id, "rate": fixtures[index].rate,
				"suite": fixtures[index].suite, "result": result})
			_check(_unvec(result.position).is_finite() and _unvec(result.velocity).is_finite(),
				"Invalid stability response")
		_write("stable_response_" + str(method.name) + ".json", {"cases": rows})
		var overlaps: Array[Dictionary] = []
		for row: Dictionary in overlap_data.overlaps:
			_config = method
			_set_rule(2)
			_set_pose(row.case.angle)
			var item := _main.flippers.items[int(row.case.side)] as TableFlipper
			var source := item.plan_motion(row.case.angle == 0.0, 18.0,
				600.0 if row.case.angle == 0.0 else 420.0)
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(1.0 / 60.0, row.case.angle == 0.0, row.case.angle == 0.0)
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_main.ball.gravity = 0.0
			_main.ball.collision_mask = 8 << int(row.case.side)
			_reset_body(row.case, _unvec(row.case.start), Vector2.ZERO)
			_main.ball.advance(1.0 / 60.0, [source])
			overlaps.append({"case": row.case, "result": _result(_motion as Trace)})
		var releases: Array[Dictionary] = []
		for row: Dictionary in release_data.cases:
			releases.append({"case": row.case, "moving": row.moving, "rate": row.rate,
				"result": _release_fixture(row.case, row.moving, row.rate, method)})
		_write("stable_overlap_" + str(method.name) + ".json", {"overlaps": overlaps,
			"releases": releases})
		print("Stability validation: ", method.name, "; normal=", rows.size(),
			"; overlaps=", overlaps.size(), "; releases=", releases.size())
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	var filename := "stable_validation_segmented.json" if "--segmented" in OS.get_cmdline_user_args() else "stable_validation.json"
	if "--finish" in OS.get_cmdline_user_args():
		filename = "stable_validation_finish.json"
	_write(filename, {"checks": _checks, "failures": _failures,
		"production_sha256": hashes})
	quit(0 if _failures == 0 else 1)
