extends "res://experiments/flippers/tests/release_audit.gd"

const TRIALS: Array[Dictionary] = [
	{"name": "baseline", "rule": 2, "separation": true, "budgets": false,
		"policy": 0, "limit": 12.0, "unlimited": false},
	{"name": "safe12", "rule": 2, "separation": true, "budgets": false,
		"policy": 2, "limit": 12.0, "unlimited": false},
	{"name": "unlimited", "rule": 2, "separation": true, "budgets": false,
		"policy": 2, "limit": 12.0, "unlimited": true},
]


func _run() -> void:
	_read_inputs()
	var hashes := _production_hashes()
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var contracts := await _contracts()
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/release_grid.json"))
	var grid: Array[Dictionary] = []
	for row: Dictionary in previous.cases:
		var methods := {}
		for config: Dictionary in TRIALS:
			methods[config.name] = _release_fixture(row.case, row.moving, row.rate, config)
			if config.name != "unlimited":
				var expected: Dictionary = row.methods[config.name]
				_check(_unvec(methods[config.name].position).distance_to(_unvec(expected.position)) < 0.001,
					"Limited policy control changed position")
				_check(_unvec(methods[config.name].velocity).distance_to(_unvec(expected.velocity)) < 0.01,
					"Limited policy control changed velocity")
		grid.append({"case": row.case, "moving": row.moving, "rate": row.rate, "methods": methods})
	_write("unlimited_grid.json", {"checks": _checks, "failures": _failures, "cases": grid})
	var integration := {}
	for config: Dictionary in TRIALS:
		_config = config
		_set_rule(2)
		integration[config.name] = {"near_enemy": await _near_grid(), "population": await _population_grid()}
		print("Unlimited integration: ", config.name)
	var regression := _unlimited_regression()
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("unlimited_audit.json", {"checks": _checks, "failures": _failures, "trials": TRIALS,
		"integration": integration, "contracts": contracts, "regression": regression,
		"production_sha256": hashes,
		"scope": "Only distance gate removed; same candidates, direction/path checks, failure termination, B detector and shared eight contacts"})
	print("Unlimited checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _attach_recorder(ball: PinballBall) -> void:
	super._attach_recorder(ball)
	(ball._motion as ReleaseTrace).recovery.distance_limited = not _config.get("unlimited", false)


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	var observed := _result(recorder as Trace)
	var recovery := (recorder as ReleaseTrace).recovery
	var overlaps := recovery.contacts(recorder.body.global_position, 0.0, recovery._duration)
	var state := {"update": result.updates - 1, "ball_id": str(recorder.body.get_instance_id()),
		"position": _vec(recorder.body.global_position), "velocity": _vec(recorder.body.velocity),
		"guard_active": observed.guard_active, "unresolved": observed.unresolved,
		"contacts": recorder.events.size(), "shots": observed.shots,
		"max_correction_px": observed.max_correction_px, "discarded_ms": observed.discarded_ms,
		"flipper_depth_px": 0.0, "world_contacts": recovery.world_contacts(recorder.body.global_position),
		"release_downward_exit": false, "release_below_to_reset": false,
		"release_opening_exit": false,
		"opening_exit": _main.boundary.has_exited(recorder.body.global_position, recorder.radius),
		"below_reset": _main.boundary.to_local(recorder.body.global_position).y > _main.boundary.bottom + 120.0}
	for hit: Dictionary in overlaps:
		state.flipper_depth_px = maxf(state.flipper_depth_px, hit.depth)
	if observed.release_correction_px > 0.0:
		_check(observed.release.flipper_clear_after, "Accepted release correction still touches flipper")
		_check(observed.release.world_after.is_empty(), "Accepted release correction overlaps world")
		var after := _unvec(observed.release.after_correction)
		state.release_below_to_reset = _main.boundary.to_local(after).y > _main.boundary.bottom + 120.0
		state.release_opening_exit = _main.boundary.has_exited(after, recorder.radius)
		for item: TableFlipper in _main.flippers.items:
			if float(observed.release.correction[1]) > 0.0 and after.y >= item.fixed_bottom + recorder.radius:
				state.release_downward_exit = true
	if not result.has("trajectory"):
		result["trajectory"] = []
	result.trajectory.append(state)
	_check(recorder.body.global_position.is_finite(), "Non-finite ball position")


func _unlimited_regression() -> Dictionary:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var extras: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_response.json"))
	var fixtures: Array = previous.cases.duplicate()
	fixtures.append_array(extras.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	for index: int in fixtures.size():
		for config: Dictionary in TRIALS:
			var value := _policy_replay(fixtures[index], config)
			var expected: Dictionary = golden.cases[index].methods.combined
			_check(_unvec(value.position).distance_to(_unvec(expected.position)) < 0.001,
				"Unguarded regression changed position")
			_check(_unvec(value.velocity).distance_to(_unvec(expected.velocity)) < 0.01,
				"Unguarded regression changed velocity")
	return {"cases": fixtures.size(), "trials": TRIALS.size()}
