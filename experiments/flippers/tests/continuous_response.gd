extends "res://experiments/flippers/tests/independent_audit.gd"

const ContinuousMotion = preload("res://experiments/flippers/tests/continuous_motion.gd")

var _step_rows: Array[Dictionary] = []


func _run() -> void:
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	_check(detection.eligible_for_response, "D2 detector has not passed the response gate")
	if _failures > 0:
		quit(1)
		return
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	for saved: Dictionary in previous.cases:
		var input: Dictionary = _inputs[int(saved.id)]
		var duration: float = 1.0 / saved.rate
		var outputs := {}
		for custom: bool in [false, true]:
			var swing := _prepare(input)
			_main.ball.collision_mask = 8
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(duration, not input.raised, not input.raised)
			_full_custom = custom
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_reset_body(input, _unvec(saved.start), _unvec(saved.velocity))
			var plans: Array[PinballFlipper.Swing] = []
			if swing != null:
				plans.append(swing)
			_main.ball.advance(duration, plans)
			var recorder := _motion as Recorder
			var result := {"position": _vec(_main.ball.global_position), "velocity": _vec(_main.ball.velocity),
				"contacts": recorder.events.size(), "discarded_ms": recorder.discarded_seconds * 1000.0,
				"unresolved": recorder.unresolved if custom else 0, "shots": 0, "max_correction": 0.0}
			for event: Dictionary in recorder.events:
				result.shots += int(event.shot)
				result.max_correction = maxf(result.max_correction, event.correction_px)
			result["first"] = recorder.events[0].duplicate(true) if not recorder.events.is_empty() else {
				"found": false, "shot": false, "end": _vec(_unvec(saved.start) + _unvec(saved.velocity) * duration),
				"velocity": saved.velocity, "correction_px": 0.0}
			if recorder.discarded_seconds > 0.0:
				result["cap_trace"] = recorder.events.duplicate(true)
			if custom and recorder.unresolved > 0:
				result["unresolved_reasons"] = recorder.reasons.duplicate()
			outputs["continuous" if custom else "baseline"] = result
			_check(_main.ball.get_collision_exceptions().is_empty(), "D2 collision exclusions leaked")
		_check(_unvec(outputs.baseline.position).distance_to(_unvec(saved.sampled.frame_guard3.frame_end)) < 0.001,
			"Baseline B changed during response comparison")
		_step_rows.append({"id": saved.id, "rate": saved.rate, "suite": saved.suite,
			"ambiguous": saved.ambiguous, "reference": saved.reference,
			"baseline": outputs.baseline, "continuous": outputs.continuous})
	var integration := await _integration()
	_check(integration.get("near_enemy", []).size() == 168, "D2 near-enemy integration did not finish")
	var transitions := _transitions()
	var ordering := await _rotating_wall_order()
	_main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/continuous_response.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"replay": _step_rows, "integration": integration, "transitions": transitions,
		"ordering": ordering, "scope": "B versus D2 only on existing rotating plans; static contacts remain native"}, "\t"))
	print("Continuous response checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := ContinuousMotion.new(ball) if _full_custom else Recorder.new(ball)
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	if recorder is ContinuousMotion:
		result["unresolved"] = result.get("unresolved", 0) + recorder.unresolved
		if not recorder.reasons.is_empty():
			result["unresolved_reasons"] = recorder.reasons.duplicate()
			result["unresolved_context"] = recorder.details.duplicate(true)
			result["invalid"] = true


func _rotating_wall_order() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for custom: bool in [false, true]:
		for difference: float in [-0.002, -0.0001, 0.0, 0.0001, 0.002]:
			_full_custom = custom
			_reset_integration()
			_main.ball.gravity = 0.0
			var item := _main.flippers.items[0] as TableFlipper
			var points := item.world_polygon_at(item.global_transform)
			var edge := points[1] - points[0]
			var normal := Vector2(edge.y, -edge.x).normalized()
			var start := points[0].lerp(points[1], 0.65) + normal * 30.0
			var incoming := Vector2(600, 1200)
			var plans := _main.flippers.plan_motion(true, false)
			var reference := _oracle(item, plans[0], item.global_transform,
				start, incoming, 24.0, 1.0 / 60.0)
			_check(not reference.hit.is_empty(), "Rotating wall fixture has no plate contact")
			var plate_time: float = reference.hit.time
			var wall_time := plate_time + difference
			_check(wall_time > 0.0, "Wall starts overlapping the ball")
			var wall := StaticBody2D.new()
			wall.name = "OrderWall"
			wall.collision_layer = 2
			var collision := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(6, 200)
			collision.shape = rectangle
			wall.add_child(collision)
			_main.get_node("Playfield").add_child(wall)
			wall.global_position = Vector2(start.x + incoming.x * wall_time + 27.0, start.y)
			wall.force_update_transform()
			_main.ball.reset_at(start, incoming)
			await physics_frame
			_main.flippers.advance(1.0 / 60.0, true, false)
			_main.ball.advance(1.0 / 60.0, plans)
			var recorder := _main.ball._motion as Recorder
			_check(not recorder.events.is_empty(), "Rotating wall contact was not processed")
			rows.append({"custom": custom, "difference_ms": difference * 1000.0,
				"reference_plate_ms": plate_time * 1000.0, "reference_wall_ms": wall_time * 1000.0,
				"tie_band": absf(difference) < 0.0002,
				"reference_first": "OrderWall" if difference < 0.0 else "LeftFlipper",
				"first": recorder.events[0].target, "events": recorder.events.duplicate(true),
				"unresolved": recorder.unresolved if custom else 0,
				"discarded_ms": recorder.discarded_seconds * 1000.0})
			wall.free()
	return rows
