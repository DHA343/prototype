extends "res://experiments/flippers/tests/quad_audit.gd"

const Continuous = preload("res://experiments/flippers/continuous_swing.gd")


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var extra: Array = detection.cases.filter(func(row: Dictionary) -> bool: return row.suite == "moving_edges") \
		.map(func(row: Dictionary) -> Dictionary: return row.case)
	for group: String in ["original60", "moving_edges"]:
		for run in 8:
			for offset in 3:
				var mode := (run + offset) % 3
				var measured := _measure_group(_inputs if group == "original60" else extra, group, mode)
				if run > 0:
					measured.merge({"run": run, "mode": mode, "group": group})
					rounds.append(measured)
	_main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/quad_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"rounds": rounds,
		"scope": "detector only, rotating plans in 876 inputs at 60Hz; no response; setup excluded"}, "\t"))
	print("Quad benchmark rounds: ", rounds.size())
	quit(0)


func _measure_group(inputs: Array, group: String, mode: int) -> Dictionary:
	var total := 0
	var evaluations := 0
	var unresolved := 0
	var queries := 0
	for input: Dictionary in inputs:
		var source: PinballFlipper.Swing
		var duration := 1.0 / 60.0
		if group == "original60":
			source = _prepare(input)
		else:
			_main.flippers.raise_speed = 600.0
			_main.flippers.return_speed = 420.0
			_set_fixed_pose(input.angle)
			var item := _main.flippers.items[int(input.side)] as TableFlipper
			source = item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
			duration = 1.0 / input.rate
		if source == null:
			continue
		var swing := source
		if mode == 1:
			swing = _copy_swing(source)
		elif mode == 2:
			swing = Continuous.new()
			for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
				swing.set(property, source.get(property))
		var began := Time.get_ticks_usec()
		swing.sweep(_unvec(input.start), _unvec(input.velocity).limit_length(3600.0),
			input.radius, 0.0, duration, _main.flippers.power_equalization)
		total += Time.get_ticks_usec() - began
		queries += 1
		if mode > 0:
			evaluations += swing.get("evaluations")
		if mode == 2:
			unresolved += swing.get("unresolved")
	return {"queries": queries, "total_us": total, "evaluations": evaluations, "unresolved": unresolved}
