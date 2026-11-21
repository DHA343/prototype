extends "res://experiments/flippers/tests/refinement_audit.gd"


func _run() -> void:
	_make_main(false)
	await physics_frame
	await physics_frame
	_set_pose(0.0)
	var item := _main.flippers.items[0] as TableFlipper
	var source := item.plan_motion(true, 18.0, 600.0)
	var polygon := item.world_polygon_at(item.global_transform)
	var center := Vector2.ZERO
	for point: Vector2 in polygon:
		center += point / 4.0
	var initial := _candidate(source, 4) as Refined
	var hit := initial._sample(center, Vector2.ZERO, 6.0, 0.0, 0.0,
		0.0, _main.flippers.power_equalization, Callable())
	_check(not hit.is_empty() and initial.no_previous == 1 and initial.extra_checks == 0,
		"Initial overlap must not be refined")
	var calls: Array[int] = [0]
	var accepted_later := _candidate(source, 4) as Refined
	hit = accepted_later._sample(center, Vector2.RIGHT, 6.0, 0.0, 0.001,
		0.0, _main.flippers.power_equalization, func(_contact: Dictionary) -> bool:
			calls[0] += 1
			return calls[0] > 1)
	_check(not hit.is_empty() and accepted_later.previous_contact == 1
		and accepted_later.extra_checks == 0, "Rejected overlap is not geometrically clear")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json")).cases.filter(
		func(row: Dictionary) -> bool: return row.suite == "moving_edges" and int(row.id) == 87)[0]
	var fixture := _fixture(saved)
	var fallback := _candidate(fixture.source, 4) as Refined
	calls[0] = 0
	hit = fallback.sweep(fixture.start, fixture.velocity, fixture.radius,
		0.0, fixture.duration, _main.flippers.power_equalization, func(_contact: Dictionary) -> bool:
			calls[0] += 1
			return calls[0] == 1)
	var baseline: Dictionary = fixture.source.sweep(fixture.start, fixture.velocity, fixture.radius,
		0.0, fixture.duration, _main.flippers.power_equalization)
	_check(not hit.is_empty() and fallback.final_invalid == 1 and fallback.refined == 0,
		"Rejected final contact must fall back explicitly")
	_check(absf(hit.time - baseline.time) < 0.000001, "Fallback changed the coarse hit")
	_write("refinement_guards.json", {"checks": _checks, "failures": _failures,
		"initial_overlap": _counts(initial), "previous_overlap_rejected": _counts(accepted_later),
		"final_rejected": _counts(fallback)})
	_main.free()
	print("Refinement guard checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
