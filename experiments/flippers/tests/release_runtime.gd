extends RefCounted


func run(preview: Node) -> Dictionary:
	var main: PinballLab = preview.main
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.spawner.enabled = false
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/release_grid.json"))
	var fixtures: Array = golden.cases.filter(func(row: Dictionary) -> bool:
		return (not row.moving and row.rate == 60 and row.case.angle == 0 and row.case.side == 0
		and ((row.case.radius == 6 and row.case.feature == 0 and row.case.depth == 0.2)
		or (row.case.radius == 24 and row.case.feature == 0 and row.case.depth == 36))))
	var results: Array[Dictionary] = []
	var controls: Array[Dictionary] = []
	for mode: int in 6:
		for row: Dictionary in fixtures:
			var key := InputEventKey.new()
			key.keycode = KEY_1 + mode
			key.pressed = true
			preview._unhandled_key_input(key)
			main.set_physics_process(false)
			main.get_node("Playfield/ShotGuide").set_physics_process(false)
			controls.append({"mode": mode, "label": str(preview.label.text),
				"rules": main.flippers.items.map(func(item: PinballFlipper) -> int: return item.get("rule"))})
			main.flippers.reset_input()
			main.flippers.swing_angle = 18.0
			main.flippers.raise_speed = 600.0
			main.flippers.return_speed = 420.0
			main.flippers.pass_until_descending = true
			for item: PinballFlipper in main.flippers.items:
				item.angular_velocity = 0.0
				item.collision_layer = 8 << item.side
			main.ball.gravity = 1500.0
			main.ball.radius = row.case.radius
			main.ball.max_speed = 3600.0
			main.ball.hit_sound = null
			main.ball.collision_mask = 8
			main.ball.reset_at(Vector2(row.case.start[0], row.case.start[1]), Vector2(0, -1))
			main.flippers.disable_target(main.ball)
			main.ball.advance(1.0 / 60.0)
			var motion = main.ball._motion
			var failed: bool = motion.get("recovery").failed if mode > 0 else false
			results.append({"mode": mode, "radius": row.case.radius, "depth": row.case.depth,
				"position": [main.ball.global_position.x, main.ball.global_position.y],
				"velocity": [main.ball.velocity.x, main.ball.velocity.y], "unresolved": failed,
				"guard_active": main.flippers.is_target_disabled(main.ball.get_instance_id()),
				"exceptions": main.ball.get_collision_exceptions().size()})
	main.set_physics_process(true)
	preview._process(0.0)
	var stopped: bool = not main.is_physics_processing() and str(preview.label.text).contains("未解消")
	var reset := InputEventKey.new()
	reset.keycode = KEY_R
	reset.pressed = true
	preview._unhandled_key_input(reset)
	var recovered: bool = main.is_physics_processing() and not main.ball._motion.get("recovery").failed
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	var output := {"controls": controls, "results": results,
		"failure_stopped": stopped, "reset_recovered": recovered,
		"scope": "Rendered six-mode preview; shallow/deep release, lean motion"}
	var file := FileAccess.open("res://experiments/flippers/evidence/release_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	return {"controls": controls.size(), "cases": results.size()}
