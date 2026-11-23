extends "res://experiments/flippers/tests/shot_audit.gd"

const Candidate = preload("res://experiments/flippers/value_candidate.gd")
const Probe = preload("res://experiments/flippers/tests/value_motion.gd")


func _run() -> void:
	_make_main(false)
	await physics_frame
	await physics_frame
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_diagnostics.json"))
	var differences := {}
	for row: Dictionary in saved.overlaps:
		for mode: String in ["A", "N", "S", "B", "F"]:
			_set_rule(2 if mode in ["S", "B", "F"] else 0)
			_set_pose(row.case.angle)
			var item := _main.flippers.items[int(row.case.side)] as TableFlipper
			var source := item.plan_motion(row.case.angle == 0.0, 18.0,
				600.0 if row.case.angle == 0.0 else 420.0)
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(1.0 / 60.0, row.case.angle == 0.0, row.case.angle == 0.0)
			if mode in ["N", "B", "F"]:
				var candidate := Candidate.new(_main.ball)
				candidate.refined = mode == "F"
				candidate.native_response = _main.ball._resolve_contact
				_main.ball._motion = candidate
			else:
				var original := PinballMotion.new(_main.ball)
				original.native_contact = _main.ball._resolve_contact
				_main.ball._motion = original
			_main.ball.gravity = 0.0
			_main.ball.collision_mask = 8 << int(row.case.side)
			_reset_body(row.case, _unvec(row.case.start), Vector2.ZERO)
			_main.ball.advance(1.0 / 60.0, [source])
			var key: String = {"A": "current", "N": "normal_new_only",
				"S": "three", "B": "combined", "F": "combined"}[mode]
			var expected: Dictionary = row.methods[key]
			var position_delta := _main.ball.global_position.distance_to(_unvec(expected.position))
			var velocity_delta := _main.ball.velocity.distance_to(_unvec(expected.velocity))
			if position_delta >= .001 or velocity_delta >= .01:
				differences[mode] = int(differences.get(mode, 0)) + 1
			if mode != "F":
				_check(position_delta < .001, "Initial overlap position changed")
				_check(velocity_delta < .01, "Initial overlap velocity changed")
			else:
				var position := _main.ball.global_position
				var velocity := _main.ball.velocity
				_set_pose(row.case.angle)
				source = item.plan_motion(row.case.angle == 0.0, 18.0,
					600.0 if row.case.angle == 0.0 else 420.0)
				_main.flippers.pass_until_descending = true
				_main.flippers.advance(1.0 / 60.0, row.case.angle == 0.0, row.case.angle == 0.0)
				var probe := Probe.new(_main.ball)
				probe.normal_new = true
				probe.refine = true
				probe.audit_detection = false
				probe.native_response = _main.ball._resolve_contact
				_main.ball._motion = probe
				_reset_body(row.case, _unvec(row.case.start), Vector2.ZERO)
				_main.ball.advance(1.0 / 60.0, [source])
				_check(_main.ball.global_position.distance_to(position) < .001,
					"Refined overlap observer position changed")
				_check(_main.ball.velocity.distance_to(velocity) < .01,
					"Refined overlap observer velocity changed")
	_main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/value_contracts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"overlap_cases": saved.overlaps.size(), "methods": ["A", "N", "S", "B", "F"],
		"different_full_tick_results": differences,
		"scope": "A/N/S/B match saved baselines; F matches its observed implementation, later contact times may differ"}))
	print("Initial overlap checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
