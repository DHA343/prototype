extends "res://experiments/flippers/tests/independent_audit.gd"

const Continuous = preload("res://experiments/flippers/continuous_swing.gd")

var _continuous_rows: Array[Dictionary] = []
var _unresolved_rows: int = 0
var _incorrect_rows: int = 0


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var d1: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/quad_d1.json"))
	_check(d1.reference_errors.is_empty(), "D1 geometry did not pass the independent reference")
	if _failures > 0:
		quit(1)
		return
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	for input: Dictionary in saved.cases:
		var swing := _prepare(_inputs[int(input.id)])
		if swing != null:
			_continuous_rows.append(_evaluate(swing.flipper, swing, _unvec(input.start),
				_unvec(input.velocity), input.radius, 1.0 / input.rate,
				input.reference, input.ambiguous, {"suite": input.suite, "id": input.id, "rate": input.rate}))
		if int(input.id) % 150 == 0:
			print("Continuous existing: ", _continuous_rows.size())
			await process_frame
	var extra := _static_cases(false)
	for index in extra.size():
		var input: Dictionary = extra[index]
		_set_pose(input.angle)
		var item := _main.flippers.items[int(input.side)] as TableFlipper
		var swing := item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
		var duration: float = 1.0 / input.rate
		var start := _unvec(input.start)
		var velocity := _unvec(input.velocity).limit_length(3600.0)
		var reference := _oracle(item, swing, item.global_transform, start, velocity, input.radius, duration)
		_check(reference.density_delta_ms < 0.01, "Moving edge reference is unstable")
		var expected := {"found": not reference.hit.is_empty(), "shot": false}
		if expected.found:
			expected.merge({"time_ms": reference.hit.time * 1000.0, "point": _vec(reference.hit.point),
				"normal": _vec(reference.hit.normal)})
			expected.shot = _is_shot(reference.hit, velocity)
		_continuous_rows.append(_evaluate(item, swing, start, velocity, input.radius, duration,
			expected, absf(reference.min_gap) < 0.1,
			{"suite": "moving_edges", "id": index, "rate": input.rate, "case": input}))
		if index % 200 == 0:
			print("Continuous moving edges: ", index, "/", extra.size())
			await process_frame
	var file := FileAccess.open("res://experiments/flippers/evidence/continuous_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"cases": _continuous_rows, "unresolved": _unresolved_rows, "incorrect": _incorrect_rows,
		"gap_tolerance": Continuous.GAP_TOLERANCE, "search_limit": Continuous.MAX_SEARCH,
		"scope": "D2 detector only; current broadphase and stop split retained; no fixed-interval sampling",
		"eligible_for_response": _unresolved_rows == 0 and _incorrect_rows == 0}, "\t"))
	_main.free()
	print("Continuous checks: ", _checks, "; failures: ", _failures,
		"; unresolved: ", _unresolved_rows, "; incorrect: ", _incorrect_rows)
	quit(0 if _failures == 0 else 1)


func _evaluate(
	item: TableFlipper, source: PinballFlipper.Swing, start: Vector2,
	velocity: Vector2, radius: float, duration: float,
	reference: Dictionary, ambiguous: bool, metadata: Dictionary,
) -> Dictionary:
	var swing := Continuous.new()
	for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
		swing.set(property, source.get(property))
	var before := _main.ball.global_position
	var hit := swing.sweep(start, velocity, radius, 0.0, duration, _main.flippers.power_equalization)
	var baseline := source.sweep(start, velocity, radius, 0.0, duration, _main.flippers.power_equalization)
	_check(_main.ball.global_position == before, "D2 detector moved the ball")
	var packed := _pack_continuous(hit, velocity)
	var incorrect: bool = not ambiguous and swing.unresolved == 0 \
		and (packed.found != reference.found or packed.shot != reference.shot)
	_unresolved_rows += int(swing.unresolved > 0)
	_incorrect_rows += int(incorrect)
	if packed.found and reference.found:
		packed["time_error_ms"] = absf(packed.time_ms - reference.time_ms)
		packed["point_error_px"] = _unvec(packed.point).distance_to(_unvec(reference.point))
		packed["normal_error_deg"] = absf(rad_to_deg(_unvec(packed.normal).angle_to(_unvec(reference.normal))))
	var row := metadata.duplicate(true)
	row.merge({"ambiguous": ambiguous, "reference": reference, "candidate": packed,
		"baseline": _pack_continuous(baseline, velocity), "unresolved": swing.unresolved,
		"reason": swing.unresolved_reason, "evaluations": swing.evaluations,
		"incorrect": incorrect})
	return row


func _is_shot(hit: Dictionary, velocity: Vector2) -> bool:
	return hit.is_striking and (velocity - (hit.surface_velocity as Vector2)).dot(hit.normal) < 0.0


func _pack_continuous(hit: Dictionary, velocity: Vector2) -> Dictionary:
	if hit.is_empty():
		return {"found": false, "shot": false}
	return {"found": true, "shot": _is_shot(hit, velocity), "time_ms": hit.time * 1000.0,
		"point": _vec(hit.point), "normal": _vec(hit.normal), "depth": hit.depth}
