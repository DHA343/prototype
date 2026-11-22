extends "res://experiments/flippers/tests/unlimited_audit.gd"


func _run() -> void:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/unlimited_audit.json"))
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for config: Dictionary in [TRIALS[0], TRIALS[2]]:
		_config = config
		_set_rule(2)
		var cases := await _near_grid()
		var observed: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://experiments/flippers/evidence/causal_" + str(config.name) + "_full_reference.json"))
		var record := {"policy": config.name, "cases": cases.size(),
			"old_position_max_px": 0.0, "observer_position_max_px": 0.0,
			"old_metric_differences": 0, "observer_metric_differences": 0,
			"first_divergences": []}
		for index: int in cases.size():
			var row: Dictionary = cases[index]
			var old: Dictionary = previous.integration[config.name].near_enemy[index]
			var trace: Dictionary = observed.cases[index]
			record.old_position_max_px = maxf(record.old_position_max_px,
				_unvec(row.position).distance_to(_unvec(old.position)))
			record.observer_position_max_px = maxf(record.observer_position_max_px,
				_unvec(row.position).distance_to(_unvec(trace.position)))
			for field: String in ["exhausted_updates", "unresolved"]:
				record.old_metric_differences += int(row[field] != old[field])
				record.observer_metric_differences += int(row[field] != trace[field])
			record.old_metric_differences += int(absf(row.max_correction_px - old.max_correction_px) > 0.001)
			record.observer_metric_differences += int(absf(row.max_correction_px - trace.max_correction_px) > 0.001)
			for frame: int in row.trajectory.size():
				var current: Dictionary = row.trajectory[frame]
				var other: Dictionary = trace.trajectory[frame]
				if _unvec(current.position).distance_to(_unvec(other.position)) > 0.001:
					record.first_divergences.append({"ratio": row.ratio, "gap": row.gap,
						"offset": row.offset, "frame": frame, "plain": current, "observer": other})
					break
		rows.append(record)
	_main.free()
	_write("causal_replay.json", {"checks": _checks, "failures": _failures, "cases": rows,
		"scope": "Unmodified inherited near-grid implementation; independent check of old versus observer trajectories"})
	print("Causal unmodified replay checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
