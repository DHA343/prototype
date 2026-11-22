extends "res://experiments/flippers/tests/shot_audit.gd"

const ProbeMotion = preload("res://experiments/flippers/tests/separation_motion.gd")
const Surroundings = preload("res://experiments/flippers/tests/separation_environment.gd")
const MATRIX: Array[Dictionary] = [
	{"name": "current", "rule": 0, "separation": false, "budgets": false},
	{"name": "three", "rule": 2, "separation": false, "budgets": false},
	{"name": "normal_new_only", "rule": 0, "separation": true, "budgets": false},
	{"name": "combined", "rule": 2, "separation": true, "budgets": false},
]


func _run() -> void:
	_read_inputs()
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var hashes := _production_hashes()
	_make_main(false)
	await physics_frame
	await physics_frame
	_rule_checks()
	var observations := await _environment_checks()
	var fixtures: Array = previous.cases.duplicate()
	fixtures.append_array(detection.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	var responses: Array[Dictionary] = []
	for saved: Dictionary in fixtures:
		var methods := {}
		for config: Dictionary in MATRIX:
			methods[config.name] = _policy_replay(saved, config)
		if not saved.has("case"):
			_check(_unvec(methods.current.position).distance_to(_unvec(saved.sampled.frame_guard3.frame_end)) < 0.001,
				"Production baseline position changed")
			_check(_unvec(methods.current.velocity).distance_to(_unvec(saved.sampled.frame_guard3.frame_velocity)) < 0.01,
				"Production baseline velocity changed")
		responses.append({"id": saved.id, "rate": saved.rate, "suite": saved.suite,
			"case": saved.get("case", {}), "ambiguous": saved.ambiguous, "methods": methods})
		if responses.size() % 750 == 0:
			print("Separation matrix: ", responses.size(), "/4644")
			await process_frame
	_write("separation_response.json", {"checks": _checks, "failures": _failures,
		"cases": responses, "matrix": MATRIX, "scope": "B detection and shared 8 contacts in all four configurations"})
	var overlaps := _matrix_overlaps()
	var focused := _matrix_focused(previous.cases, detection.cases)
	var integration := {}
	for config: Dictionary in MATRIX:
		_config = config
		_detector = "B"
		_set_rule(int(config.rule))
		integration[config.name] = await _integration()
		_check(integration[config.name].near_enemy.size() == 84, "Near-enemy fixture count changed")
		print("Separation integration: ", config.name)
	var transitions := _matrix_transitions()
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("separation_diagnostics.json", {"checks": _checks, "failures": _failures,
		"overlaps": overlaps, "focused": focused, "integration": integration,
		"transitions": transitions, "environment_checks": observations, "production_sha256": hashes,
		"scope": "A-D state and same-flipper history separate; E observations never alter response"})
	print("Separation checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _read_inputs() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	for row: Dictionary in previous.cases:
		_original[_key(row)] = row


func _production_hashes() -> Dictionary:
	var hashes := {}
	for path: String in ["pinball/flipper.gd", "pinball/table_flipper.gd", "pinball/motion.gd",
		"pinball/flippers.gd", "pinball/ball.gd", "main/main.gd", "main/main.tscn", "enemies/enemy.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	return hashes


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := ProbeMotion.new(ball)
	recorder.detector = _detector
	recorder.normal_for_new_contact = _config.separation
	recorder.split_budgets = false
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _result(recorder: Trace, cpu: int = 0) -> Dictionary:
	var result := super._result(recorder, cpu)
	result.merge(_event_counts(recorder.events))
	return result


func _event_counts(events: Array[Dictionary]) -> Dictionary:
	var result := {"states": {"A": 0, "B": 0, "C": 0, "D": 0, "other": 0},
		"repeat_A": 0, "C_without_prior_contact": 0, "E_before": 0,
		"E_after": 0, "E_introduced": 0, "E_path_only": 0, "E_limited": 0,
		"positive_depth": 0, "zero_depth": 0}
	for event: Dictionary in events:
		var state: String = event.get("state_class", "other")
		result.states[state] += 1
		result.repeat_A += int(state == "A" and event.get("same_flipper_contact_before", false))
		result.C_without_prior_contact += int(state == "C" and not event.get("same_flipper_contact_before", false))
		if event.get("depth_px") != null:
			result.positive_depth += int(float(event.depth_px) > 0.0)
			result.zero_depth += int(float(event.depth_px) == 0.0)
		var surroundings: Dictionary = event.get("environment", {})
		if surroundings.is_empty():
			continue
		result.E_before += int(not surroundings.before.is_empty())
		result.E_after += int(not surroundings.after.is_empty())
		result.E_introduced += int(not surroundings.introduced.is_empty())
		result.E_path_only += int(surroundings.path_only)
		result.E_limited += int(surroundings.limited)
	return result


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	var counts := _event_counts(recorder.events)
	if not result.has("observed"):
		result["observed"] = counts
	else:
		for state: String in counts.states:
			result.observed.states[state] += counts.states[state]
		for key: String in counts:
			if key != "states":
				result.observed[key] += counts[key]
	for event: Dictionary in recorder.events:
		if event.state_class in ["B", "C", "D"] or event.get("same_flipper_contact_before", false):
			if not result.has("state_events"):
				result["state_events"] = []
			var history := event.duplicate(true)
			history["update_index"] = result.updates - 1
			history["ball_id"] = str(recorder.body.get_instance_id())
			result.state_events.append(history)
		var surroundings: Dictionary = event.get("environment", {})
		if not surroundings.is_empty() and (not surroundings.before.is_empty()
			or not surroundings.after.is_empty() or surroundings.path_blocked):
			if not result.has("E_events"):
				result["E_events"] = []
			var saved := event.duplicate(true)
			saved["update_index"] = result.updates - 1
			saved["ball_id"] = str(recorder.body.get_instance_id())
			result.E_events.append(saved)


func _matrix_overlaps() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_detector = "B"
	for input: Dictionary in _static_cases(true):
		var methods := {}
		for config: Dictionary in MATRIX:
			_config = config
			_set_rule(int(config.rule))
			_set_pose(input.angle)
			var item := _main.flippers.items[int(input.side)] as TableFlipper
			var source := item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(1.0 / 60.0, input.angle == 0.0, input.angle == 0.0)
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_main.ball.gravity = 0.0
			_main.ball.collision_mask = 8 << int(input.side)
			_reset_body(input, _unvec(input.start), Vector2.ZERO)
			_main.ball.advance(1.0 / 60.0, [source])
			methods[config.name] = _result(_motion as Trace)
		for names: Array in [["current", "normal_new_only"], ["three", "combined"]]:
			_check(_unvec(methods[names[0]].position).distance_to(_unvec(methods[names[1]].position)) < 0.001,
				"Normal policy changed initial overlap recovery")
		rows.append({"case": input, "methods": methods})
	return rows


func _matrix_focused(originals: Array, detectors: Array) -> Array[Dictionary]:
	var cases: Array = originals.filter(func(row: Dictionary) -> bool:
		return row.rate == 30 and int(row.id) in [405, 465, 525])
	cases.append_array(detectors.filter(func(row: Dictionary) -> bool:
		return row.has("case") and int(row.id) in [615, 623]))
	var rows: Array[Dictionary] = []
	for saved: Dictionary in cases:
		var methods := {}
		for config: Dictionary in MATRIX:
			for detector: String in ["B", "B+4", "D2"]:
				methods[config.name + ":" + detector] = _policy_replay(saved, config, detector)
		rows.append({"id": saved.id, "rate": saved.rate, "suite": saved.suite, "methods": methods})
	return rows


func _matrix_transitions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_detector = "B"
	for config: Dictionary in MATRIX:
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


func _environment_checks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for initial: bool in [false, true]:
		for segment: bool in [false, true]:
			for released: bool in [false, true]:
				var state := ProbeMotion.state_class(initial, segment, released)
				_check(state == ("D" if initial and released else ("B" if initial else ("C" if segment else "A"))),
					"Contact state classification failed")
	_main.flippers.reset_input()
	_main.ball.collision_mask = 2
	var wall := StaticBody2D.new()
	wall.name = "CorrectionProbeWall"
	wall.collision_layer = 2
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1, 80)
	collision.shape = rectangle
	wall.add_child(collision)
	_main.get_node("Playfield").add_child(wall)
	wall.global_position = Vector2(960, 850)
	wall.force_update_transform()
	await physics_frame
	var observer := Surroundings.new()
	var plans: Array[PinballFlipper.Swing] = []
	var before := _main.ball.global_position
	for fixture: Dictionary in [
		{"name": "path_only", "start": Vector2(930, 850), "motion": Vector2(60, 0)},
		{"name": "introduced", "start": Vector2(930, 850), "motion": Vector2(25, 0)},
		{"name": "already_inside", "start": Vector2(960, 850), "motion": Vector2(30, 0)},
	]:
		var output := observer.observe(_main.ball, 6.0, null, fixture.start, fixture.motion, _main.flippers, plans, 0.0)
		if fixture.name == "path_only":
			_check(output.path_only, "Thin-wall crossing must be detected even with clear endpoints")
		elif fixture.name == "introduced":
			_check(output.before.is_empty() and output.introduced.size() == 1, "New endpoint overlap was not detected")
		else:
			_check(output.before.size() == 1 and output.after.is_empty(), "Initial obstacle overlap was not recorded")
		rows.append({"case": fixture.name, "result": output})
	_check(_main.ball.global_position == before, "Observation moved the ball")
	wall.free()
	_main.ball.collision_mask = 16
	plans = _main.flippers.plan_motion(true, true)
	var other := _main.flippers.items[1] as TableFlipper
	var polygon := other.world_polygon_at(other.global_transform)
	var edge := polygon[1] - polygon[0]
	var normal := Vector2(edge.y, -edge.x).normalized()
	var point := polygon[0].lerp(polygon[1], 0.65) + normal * 5.9
	_main.flippers.advance(1.0 / 60.0, true, true)
	var final_pose := other.global_transform
	var observation := observer.observe(_main.ball, 6.0, _main.flippers.items[0], point,
		Vector2.ZERO, _main.flippers, plans, 0.0)
	_check(observation.before.any(func(actor: Dictionary) -> bool: return actor.name == "RightFlipper"),
		"Other flipper must use the contact-time pose")
	_check(other.global_transform == final_pose, "Observation changed the other flipper pose")
	rows.append({"case": "other_flipper_at_contact_time", "result": observation})
	_main.flippers.reset_input()
	return rows
