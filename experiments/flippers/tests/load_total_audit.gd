extends "res://experiments/flippers/tests/load_audit.gd"

const TotalWorld = preload("res://experiments/flippers/tests/load_total_world.gd")


func _start_next() -> void:
	if index >= jobs.size():
		_save()
		return
	current = jobs[index]
	world = TotalWorld.new()
	add_child(world)
	world.setup(current.config, int(current.mode) == 4, false)
	for attempt in 300:
		await get_tree().physics_frame
		if not world.main.routes.path_from(Vector2(800, 200), 30.0).is_empty():
			break
	world.settle_balls()
	await get_tree().physics_frame
	if not world.populate():
		get_tree().quit(1)
		return
	await get_tree().physics_frame
	frames = []
	draw_frames = []
	frame = 0
	restarted = false
	last_row = {}
	running = true


func _save() -> void:
	var file := FileAccess.open("res://experiments/flippers/evidence/load_total.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "godot": Engine.get_version_info(),
		"cpu": OS.get_processor_name(), "warmup": warmup, "samples": samples,
		"rounds": rounds, "physics_hz": 60, "results_complete": true,
		"automatic_updates_disabled": true,
		"scope": "Whole main.advance plus guide without stage clocks or probes; multiball repeats the same phases for 20 balls before launcher"}, "\t"))
	complete = true
	print("Load total audit complete: ", results.size())
	get_tree().quit(0)
