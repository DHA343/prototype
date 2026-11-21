extends "res://experiments/flippers/tests/shot_audit.gd"


func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for saved: Dictionary in data.cases:
		if saved.suite != "moving_edges" or int(saved.id) not in [615, 623]:
			continue
		var outputs := {}
		for detector: String in ["B", "B+4", "D2"]:
			outputs[detector] = _policy_replay(saved, CONFIGS[2], detector)
		rows.append({"id": saved.id, "rate": saved.rate, "case": saved.case, "methods": outputs})
	_main.free()
	_write("shot_precision.json", {"checks": _checks, "failures": _failures, "cases": rows,
		"scope": "Diagnostic replay of the two new-rule approach-sign mismatches, not an adoption of a combined method"})
	print("Shot precision checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
