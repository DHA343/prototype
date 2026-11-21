extends "res://experiments/flippers/tests/refinement_audit.gd"

const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Shot = preload("res://experiments/flippers/shot_flipper.gd")
const Trace = preload("res://experiments/flippers/tests/shot_motion.gd")
const CONFIGS: Array[Dictionary] = [
	{"name": "current", "rule": 0, "separation": false, "budgets": false},
	{"name": "without_angle", "rule": 1, "separation": false, "budgets": false},
	{"name": "three", "rule": 2, "separation": false, "budgets": false},
	{"name": "normal_new_only", "rule": 0, "separation": true, "budgets": false},
	{"name": "split_budgets", "rule": 0, "separation": false, "budgets": true},
]

var _config: Dictionary = CONFIGS[0]
var _detector: String = "B"


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	for row: Dictionary in previous.cases:
		_original[_key(row)] = row
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var hashes := {}
	for path: String in ["pinball/flipper.gd", "pinball/table_flipper.gd", "pinball/motion.gd",
		"pinball/flippers.gd", "pinball/ball.gd", "main/main.gd", "main/main.tscn", "enemies/enemy.gd"]:
		hashes[path] = FileAccess.get_sha256("res://" + path)
	_make_main(false)
	await physics_frame
	await physics_frame
	_rule_checks()
	var detectors: Array[Dictionary] = []
	for saved: Dictionary in detection.cases:
		detectors.append(_detect_policy(saved))
		if detectors.size() % 750 == 0:
			print("Shot detection: ", detectors.size(), "/4500")
			await process_frame
	_write("shot_detection.json", {"checks": _checks, "failures": _failures, "cases": detectors,
		"scope": "Same 4500 geometries; reference contact times reused, shot classification recomputed per rule"})
	var fixtures: Array = previous.cases.duplicate()
	fixtures.append_array(detection.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	var responses: Array[Dictionary] = []
	for saved: Dictionary in fixtures:
		var methods := {}
		for config: Dictionary in CONFIGS:
			methods[config.name] = _policy_replay(saved, config)
		var control: Dictionary = methods.current
		if not saved.has("case"):
			_check(_unvec(control.position).distance_to(_unvec(saved.sampled.frame_guard3.frame_end)) < 0.001,
				"Current B position differs from stored production result")
			_check(_unvec(control.velocity).distance_to(_unvec(saved.sampled.frame_guard3.frame_velocity)) < 0.01,
				"Current B velocity differs from stored production result")
		_check_prefix(control.events, methods.split_budgets.events)
		if control.discarded_ms == 0.0:
			_check(_unvec(control.position).distance_to(_unvec(methods.split_budgets.position)) < 0.001,
				"Separate budgets changed an uncapped result")
		responses.append({"suite": saved.suite, "id": saved.id, "rate": saved.rate,
			"ambiguous": saved.ambiguous, "methods": methods,
			"case": saved.get("case", {})})
		if responses.size() % 750 == 0:
			print("Shot response: ", responses.size(), "/4644")
			await process_frame
	_write("shot_response.json", {"checks": _checks, "failures": _failures, "cases": responses})
	var overlaps := _overlap_replays()
	var focused := _focused(previous.cases)
	var integration := {}
	for config: Dictionary in CONFIGS:
		_config = config
		_detector = "B"
		_set_rule(int(config.rule))
		integration[config.name] = await _integration()
		_check(integration[config.name].near_enemy.size() == 84, "Near-enemy fixture count changed")
		print("Shot integration: ", config.name)
	var transitions := _release_cases()
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("shot_diagnostics.json", {"checks": _checks, "failures": _failures,
		"overlaps": overlaps, "focused": focused, "integration": integration,
		"transitions": transitions, "production_sha256": hashes,
		"scope": "Independent factors; no combined shot/separation/budget variant; recovery still upward at initial overlap"})
	print("Shot audit checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _make_main(_counted: bool) -> void:
	_main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(_main, 0)
	_main.get_node("EnemySpawner").enabled = false
	root.add_child(_main)
	_main.set_physics_process(false)
	_main.get_node("Playfield/ShotGuide").set_physics_process(false)
	_check(not _main.is_physics_processing(), "Automatic main updates must be disabled")
	_main.ball.gravity = 0.0
	_main.ball.max_speed = 3600.0
	_main.ball.hit_sound = null
	_main.ball.collision_mask = 8
	_main.flippers.items[0].collision_layer = 8
	_main.flippers.items[1].collision_layer = 16
	_attach_recorder(_main.ball)
	_motion = _main.ball._motion


func _corner_checks() -> void:
	for side in 2:
		_set_pose(0.0)
		var item := _main.flippers.items[side] as Shot
		item.angular_velocity = item._direction * deg_to_rad(180.0)
		var polygon := item.world_polygon_at(item.global_transform)
		for index in 2:
			var normal := Vector2(-0.98 if index == 0 else 0.98, -0.2).normalized()
			var center := polygon[index] + normal * 5.9
			_set_rule(2)
			var hit := item._contact_at(center, 6.0, item.global_transform,
				item.angular_velocity, _main.flippers.power_equalization)
			_check(not hit.is_empty() and hit.is_striking, "Upper corner must remain a shot face")
			if hit.is_empty():
				continue
			_check((hit.normal as Vector2).dot(item.strike_normal()) < 0.5,
				"Corner fixture does not cross the old angle limit")
			var expected := item._upper_velocity(item._point_velocity(
				hit.point - item.global_position, item.tip_position() - item.global_position,
				item.angular_velocity, _main.flippers.power_equalization), item.global_transform)
			_check((hit.strike_surface_velocity as Vector2).distance_to(expected) < 0.01,
				"New shot must recompute equalized surface velocity")
			_set_rule(0)
			var old := item._contact_at(center, 6.0, item.global_transform,
				item.angular_velocity, _main.flippers.power_equalization)
			_check(not old.is_striking and (old.surface_velocity as Vector2).distance_to(hit.surface_velocity) < 0.001,
				"Angle-policy comparison changed physical surface velocity")


func _set_rule(rule: int) -> void:
	for item: Shot in _main.flippers.items:
		item.rule = rule as Shot.Rule


func _detect_policy(saved: Dictionary) -> Dictionary:
	var outputs := {}
	var expected := {}
	for rule in 3:
		_set_rule(rule)
		var fixture := _fixture(saved)
		var source: PinballFlipper.Swing = fixture.source
		var hit := source.sweep(fixture.start, fixture.velocity, fixture.radius,
			0.0, fixture.duration, _main.flippers.power_equalization)
		var result := _pack_hit(hit, fixture.velocity)
		outputs[CONFIGS[rule].name] = result
		var reference := {"found": saved.reference.found, "shot": false}
		if reference.found:
			var time: float = saved.reference.time_ms / 1000.0
			var pose := _pose(source.flipper, source, source.flipper.global_transform, time)
			var omega := source.speed if time < source.stop_time else 0.0
			var oracle_hit := source.flipper._contact_at(fixture.start + fixture.velocity * time,
				fixture.radius + 0.0005, pose, omega, _main.flippers.power_equalization)
			_check(not oracle_hit.is_empty(), "Saved contact cannot be represented")
			if not oracle_hit.is_empty():
				reference.shot = _reference_shot(source.flipper, oracle_hit, pose, omega, fixture.velocity, rule)
				reference.merge({"time_ms": saved.reference.time_ms, "point": _vec(oracle_hit.point),
					"normal": _vec(oracle_hit.normal), "is_striking": oracle_hit.is_striking})
		expected[CONFIGS[rule].name] = reference
		if rule > 0:
			_check(result.found == outputs.current.found, "Policy changed collision presence")
			if result.found:
				_check(absf(result.time_ms - outputs.current.time_ms) < 0.000001,
					"Policy changed collision time")
		else:
			_check(result.found == saved.baseline.found and result.shot == saved.baseline.shot,
				"Current policy differs from saved B")
	return {"suite": saved.suite, "id": saved.id, "rate": saved.rate, "ambiguous": saved.ambiguous,
		"case": saved.get("case", {}), "methods": outputs, "references": expected}


func _reference_shot(
	item: PinballFlipper, hit: Dictionary, pose: Transform2D,
	omega: float, incoming: Vector2, rule: int,
) -> bool:
	if omega * item._direction <= 0.0 or (incoming - (hit.surface_velocity as Vector2)).dot(hit.normal) >= 0.0:
		return false
	var polygon := (item as TableFlipper).world_polygon_at(pose)
	var on_top := Geometry2D.get_closest_point_to_segment(hit.point, polygon[0], polygon[1]).distance_squared_to(hit.point) < 0.000004
	var x := (pose.affine_inverse() * (hit.point as Vector2)).x
	var upper := pose.basis_xform(Vector2(0, item._direction)).normalized()
	return on_top and (rule == 2 or x > 0.0) and (rule != 0 or (hit.normal as Vector2).dot(upper) > 0.5)


func _policy_replay(saved: Dictionary, config: Dictionary, detector: String = "B") -> Dictionary:
	_config = config
	_detector = detector
	_set_rule(int(config.rule))
	var fixture := _fixture(saved)
	var source: PinballFlipper.Swing = fixture.source
	var held: bool = saved.case.angle == 0.0 if saved.has("case") else not _inputs[int(saved.id)].raised
	_main.flippers.pass_until_descending = true
	_main.flippers.advance(fixture.duration, held, held)
	_attach_recorder(_main.ball)
	_motion = _main.ball._motion
	_main.ball.gravity = 0.0
	_main.ball.collision_mask = (8 << source.flipper.side) if source != null else 8
	_reset_body({"radius": fixture.radius}, fixture.start, fixture.velocity)
	var plans: Array[PinballFlipper.Swing] = []
	if source != null:
		plans.append(source)
	var began := Time.get_ticks_usec()
	_main.ball.advance(fixture.duration, plans)
	var cpu := Time.get_ticks_usec() - began
	_check(_main.ball.get_collision_exceptions().is_empty(), "Collision exclusions leaked")
	return _result(_main.ball._motion as Trace, cpu)


func _result(recorder: Trace, cpu: int = 0) -> Dictionary:
	var maximum := 0.0
	var shots := 0
	for event: Dictionary in recorder.events:
		maximum = maxf(maximum, event.correction_px)
		shots += int(event.shot)
	return {"position": _vec(recorder.body.global_position), "velocity": _vec(recorder.body.velocity),
		"contacts": recorder.events.size(), "shots": shots, "max_correction_px": maximum,
		"discarded_ms": recorder.discarded_seconds * 1000.0, "cap_reason": recorder.cap_reason,
		"velocity_contacts": recorder.movement_contacts, "recovery_contacts": recorder.recovery_contacts,
		"guard_released": recorder.guard_released, "events": recorder.events.duplicate(true), "cpu_us": cpu}


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := Trace.new(ball)
	recorder.detector = _detector
	recorder.normal_for_new_contact = _config.separation
	recorder.split_budgets = _config.budgets
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _integration_modes() -> Array[bool]:
	return [true]


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	result["updates"] = result.get("updates", 0) + 1
	if not result.has("categories"):
		result["categories"] = {}
	for event: Dictionary in recorder.events:
		result.categories[event.category] = result.categories.get(event.category, 0) + 1
	if recorder.discarded_seconds > 0.0 or recorder.events.size() >= PinballMotion.MAX_CONTACTS or recorder.events.any(func(event: Dictionary) -> bool:
		return event.correction_px > 20.0):
		if not result.has("diagnostics"):
			result["diagnostics"] = []
		var saved := _result(recorder as Trace)
		saved["update_index"] = result.updates - 1
		result.diagnostics.append(saved)


func _focused(originals: Array) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for saved: Dictionary in originals:
		if saved.rate != 30 or int(saved.id) not in [405, 465, 525]:
			continue
		var methods := {}
		for detector: String in ["B", "B+4", "D2"]:
			for index: int in [0, 2, 3, 4]:
				methods[CONFIGS[index].name + ":" + detector] = _policy_replay(saved, CONFIGS[index], detector)
		results.append({"id": saved.id, "rate": saved.rate, "methods": methods})
	return results


func _overlap_replays() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var inputs := _static_cases(true)
	_detector = "B"
	for input: Dictionary in inputs:
		var methods := {}
		for config: Dictionary in CONFIGS:
			_config = config
			_set_rule(int(config.rule))
			_set_pose(input.angle)
			var item := _main.flippers.items[int(input.side)] as TableFlipper
			var source := item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(1.0 / 60.0, input.angle == 0.0, input.angle == 0.0)
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_main.ball.collision_mask = 8 << int(input.side)
			_main.ball.gravity = 0.0
			_reset_body(input, _unvec(input.start), Vector2.ZERO)
			_main.ball.advance(1.0 / 60.0, [source])
			methods[config.name] = _result(_motion as Trace)
		_check(_unvec(methods.current.position).distance_to(_unvec(methods.normal_new_only.position)) < 0.001,
			"New-contact separation changed initial-overlap recovery")
		rows.append({"case": input, "methods": methods})
	return rows


func _release_cases() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	_detector = "B"
	for config: Dictionary in CONFIGS:
		_config = config
		_set_rule(int(config.rule))
		for kind: String in ["release_rest", "release_held", "release_rising", "stop_now", "stop_next"]:
			_reset_integration()
			var item := _main.flippers.items[0] as TableFlipper
			if kind.begins_with("release"):
				if kind == "release_held":
					_main.flippers.advance(18.0 / 600.0, true, false)
				var polygon := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(polygon[0].lerp(polygon[1], 0.65) + Vector2.DOWN * 12, Vector2(0, -1))
				_main.flippers.disable_target(_main.ball)
			else:
				_main.flippers.advance(15.0 / 600.0, true, false)
				var polygon := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(polygon[0].lerp(polygon[1], 0.65) + Vector2.UP * 28, Vector2(0, 600))
				if kind == "stop_next":
					_main.flippers.advance(3.0 / 600.0, true, false)
			var pressed := kind != "release_rest"
			var plans := _main.flippers.plan_motion(pressed, false)
			_main.flippers.advance(1.0 / 60.0, pressed, false)
			_main.ball.advance(1.0 / 60.0, plans)
			rows.append({"mode": config.name, "case": kind, "result": _result(_motion as Trace)})
	return rows


func _check_prefix(control: Array, candidate: Array) -> void:
	_check(candidate.size() >= control.size(), "Separate budgets lost a control contact")
	for index in mini(control.size(), candidate.size()):
		_check(absf(control[index].time_ms - candidate[index].time_ms) < 0.000001 and
			_unvec(control[index].velocity).distance_to(_unvec(candidate[index].velocity)) < 0.01,
			"Separate budgets changed the common contact prefix")


func _rule_checks() -> void:
	_set_rule(2)
	for side in 2:
		_set_pose(0.0)
		var item := _main.flippers.items[side] as Shot
		var polygon := item.world_polygon_at(item.global_transform)
		for feature in 8:
			var edge := feature % 4
			var a := polygon[edge]
			var b := polygon[(edge + 1) % 4]
			var normal := Vector2((b - a).y, -(b - a).x).normalized()
			var point := a.lerp(b, 0.5)
			if feature >= 4:
				point = a
				var previous := a - polygon[(edge + 3) % 4]
				normal = (normal + Vector2(previous.y, -previous.x).normalized()).normalized()
			for direction: int in [-1, 0, 1]:
				var omega := item._direction * direction * deg_to_rad(180)
				item.angular_velocity = omega
				var hit := item._contact_at(point + normal * 5.9, 6.0,
					item.global_transform, omega, _main.flippers.power_equalization)
				_check(not hit.is_empty(), "Rule fixture has no contact")
				if hit.is_empty():
					continue
				var upper: bool = edge == 0 or (feature >= 4 and edge == 1)
				_check(hit.is_striking == (direction > 0 and upper), "Three-condition face/rise classification failed")
				_check(item.is_striking(hit.point, hit.normal) == hit.is_striking,
					"Native and swept shot predicates differ")
				if hit.is_striking:
					hit.flipper = item
					for approaching: bool in [false, true]:
						_config = CONFIGS[2]
						_attach_recorder(_main.ball)
						_motion = _main.ball._motion
						_main.flippers.pass_until_descending = true
						var incoming: Vector2 = hit.surface_velocity + (hit.normal as Vector2) * (-300 if approaching else 300)
						_reset_body({"radius": 6.0}, point + normal * 5.9, incoming)
						(_motion as Trace).begin(1.0 / 60.0)
						(_motion as Trace)._respond_to_flipper(hit)
						_check((_motion as Trace).events[0].shot == approaching,
							"Relative approach must gate the shot")
						_check(_main.flippers.is_target_disabled(_main.ball.get_instance_id()) == approaching,
							"Guard must start only on an actual shot")
						# Direct response tests bypass advance()'s normal exception cleanup.
						for excluded: PhysicsBody2D in _main.ball.get_collision_exceptions():
							_main.ball.remove_collision_exception_with(excluded)
						(_motion as Trace)._guard_exceptions.clear()
	_main.ball.gravity = 0.0
	_corner_checks()
