extends "res://experiments/flippers/tests/refinement_audit.gd"


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var extra: Array = detection.cases.filter(func(row: Dictionary) -> bool:
		return row.suite == "moving_edges").map(func(row: Dictionary) -> Dictionary: return row.case)
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	for group: String in ["original60", "moving_edges"]:
		for run in 8:
			for offset in MODES.size():
				var mode := MODES[(run + offset) % MODES.size()]
				var result := _measure_refinement(_inputs if group == "original60" else extra, group, mode)
				if run > 0:
					result.merge({"run": run, "mode": _label(mode), "group": group})
					rounds.append(result)
	_main.free()
	_write("refinement_benchmark.json", {"rounds": rounds, "godot": Engine.get_version_info(),
		"scope": "Detector only, original60 828 rotating plans and moving_edges 2016; setup and copy excluded; one warmup, seven rounds; rotated order; actual production B"})
	print("Refinement benchmark rounds: ", rounds.size())
	quit(0)


func _measure_refinement(inputs: Array, group: String, mode: int) -> Dictionary:
	var total := 0
	var queries := 0
	var counts := {}
	for input: Dictionary in inputs:
		var source: PinballFlipper.Swing
		var duration := 1.0 / 60.0
		if group == "original60":
			source = _prepare(input)
		else:
			_set_pose(input.angle)
			var item := _main.flippers.items[int(input.side)] as TableFlipper
			source = item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
			duration = 1.0 / input.rate
		if source == null:
			continue
		var swing := source if mode == 0 else _candidate(source, mode)
		var start := _unvec(input.start)
		var velocity := _unvec(input.velocity).limit_length(3600.0)
		var began := Time.get_ticks_usec()
		swing.sweep(start, velocity, input.radius, 0.0, duration, _main.flippers.power_equalization)
		total += Time.get_ticks_usec() - began
		queries += 1
		if mode != 0:
			var measured := _counts(swing)
			for key: String in measured:
				counts[key] = counts.get(key, 0) + measured[key]
	return {"queries": queries, "total_us": total, "counts": counts}
