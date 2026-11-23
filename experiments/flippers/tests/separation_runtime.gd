extends RefCounted


func run(preview: Node) -> Dictionary:
	var rows: Array[Dictionary] = []
	for index: int in 8:
		for mode: int in 2:
			preview.variant = 0
			await preview.reset_case(index, mode)
			for frame: int in 3:
				preview.step_once()
				await preview.get_tree().physics_frame
			rows.append({"scene": index + 1, "mode": "S" if mode == 0 else "B",
				"initial": preview.initial.duplicate(true), "updates": preview.frames,
				"max_correction_px": preview.max_correction, "caps": preview.capped_updates,
				"first": preview.events[0].duplicate(true) if not preview.events.is_empty() else {}})
	var output := {"cases": rows, "scope": "Live rendered eight-scene preview, three updates per S/B"}
	var file := FileAccess.open("res://experiments/flippers/evidence/separation_view_runtime.json", FileAccess.WRITE)
	assert(file != null, "Cannot save visual runtime comparison")
	file.store_string(JSON.stringify(output))
	await preview.reset_case(0, 1)
	return {"scenes": 8, "methods": 2, "cases": rows.size(), "saved": "separation_view_runtime.json"}
