extends Node

const World = preload("res://experiments/flippers/tests/load_world.gd")
const CASES: Array[Dictionary] = [
	{"name": "empty", "balls": 0, "enemies": 0, "moving": false},
	{"name": "flippers", "balls": 0, "enemies": 0, "moving": true},
	{"name": "ball", "balls": 1, "enemies": 0, "moving": true},
	{"name": "enemies10", "balls": 1, "enemies": 10, "moving": true},
	{"name": "enemies30", "balls": 1, "enemies": 30, "moving": true},
	{"name": "enemies60", "balls": 1, "enemies": 60, "moving": true},
	{"name": "multiball", "balls": 20, "enemies": 30, "moving": true},
]

var world: World
var jobs: Array[Dictionary] = []
var results: Array[Dictionary] = []
var current: Dictionary = {}
var frames: Array[Dictionary] = []
var draw_frames: Array[Dictionary] = []
var index: int = 0
var frame: int = 0
var warmup: int = 60
var samples: int = 240
var rounds: int = 5
var running: bool = false
var detailed: bool = false
var rendered: bool = false
var last_draw: int = 0
var last_row: Dictionary = {}
var complete: bool = false
var restarted: bool = false


func _ready() -> void:
	rendered = DisplayServer.get_name() != "headless"
	var arguments := OS.get_cmdline_user_args()
	detailed = "--profile" in arguments
	if rendered:
		rounds = 3
		samples = 180
	if "--smoke" in arguments:
		rounds = 1
		warmup = 5
		samples = 12
	Engine.physics_ticks_per_second = 60
	for run in rounds:
		for settings: Dictionary in CASES:
			for mode: int in ([0, 4] if run % 2 == 0 else [4, 0]):
				jobs.append({"run": run, "config": settings, "mode": mode})
	_start_next.call_deferred()


func _physics_process(delta: float) -> void:
	if not last_row.is_empty():
		last_row["engine_physics_us"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000000.0
		last_row = {}
	if not running:
		return
	if frame == warmup and not restarted:
		running = false
		_restart_measurement.call_deferred()
		return
	var row := world.tick(delta, frame - warmup if restarted else frame)
	if frame >= warmup:
		row["frame"] = frame - warmup
		frames.append(row)
		last_row = row
	frame += 1
	if frame >= warmup + samples:
		running = false
		_finish_case.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if running and frame > warmup + 1 and last_draw > 0 and rendered:
		draw_frames.append({"wall_us": now - last_draw,
			"process_us": Performance.get_monitor(Performance.TIME_PROCESS) * 1000000.0,
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"objects": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)})
	last_draw = now


func _start_next() -> void:
	if index >= jobs.size():
		_save()
		return
	current = jobs[index]
	world = World.new()
	add_child(world)
	world.setup(current.config, int(current.mode) == 4, detailed)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Headless fixed-fps can advance several ticks before the navigation worker is ready.
	for attempt in 300:
		if not world.main.routes.path_from(Vector2(800, 200), 30.0).is_empty():
			break
		await get_tree().physics_frame
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


func _restart_measurement() -> void:
	world.reset_episode()
	await get_tree().physics_frame
	if not world.populate():
		get_tree().quit(1)
		return
	await get_tree().physics_frame
	restarted = true
	running = true


func _finish_case() -> void:
	await get_tree().physics_frame
	var row := current.duplicate(true)
	row.merge({"frames": frames, "draw_frames": draw_frames, "outcome": world.outcome(),
		"initial_enemies": world.enemy_starts.map(func(point: Vector2) -> Array: return [point.x, point.y])})
	results.append(row)
	world.free()
	index += 1
	if index % 14 == 0:
		print("Load audit: ", index, "/", jobs.size(), "; rendered=", rendered, "; profile=", detailed)
	_start_next.call_deferred()


func _save() -> void:
	var kind := "rendered" if rendered else ("profile" if detailed else "headless")
	var suffix := "_smoke" if "--smoke" in OS.get_cmdline_user_args() else ""
	var path := "res://experiments/flippers/evidence/load_" + kind + suffix + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "godot": Engine.get_version_info(),
		"display": DisplayServer.get_name(), "render_method": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "cpu": OS.get_processor_name(),
		"warmup": warmup, "samples": samples, "rounds": rounds, "physics_hz": 60,
		"detailed": detailed, "automatic_updates_disabled": true,
		"vsync": DisplayServer.window_get_vsync_mode(),
		"viewport": get_viewport().get_visible_rect().size, "results_complete": true}, "\t"))
	complete = true
	print("Load audit saved: ", path)
	if not rendered:
		get_tree().quit(0)
