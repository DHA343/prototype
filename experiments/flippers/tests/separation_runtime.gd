extends RefCounted


func run(preview: Node) -> Dictionary:
	var main: PinballLab = preview.main
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.spawner.enabled = false
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var results: Array[Dictionary] = []
	var controls: Array[Dictionary] = []
	for mode: int in 4:
		var key := InputEventKey.new()
		key.keycode = KEY_1 + mode
		key.pressed = true
		preview._unhandled_key_input(key)
		controls.append({"mode": mode, "label": str(preview.label.text),
			"flippers": main.flippers.items.map(func(item: PinballFlipper) -> int: return item.get("rule")),
			"motion": main.ball._motion.get_script().resource_path})
		for id: int in [96, 1885]:
			var row: Dictionary = saved.cases.filter(func(item: Dictionary) -> bool:
				return item.has("case") and int(item.id) == id)[0]
			var fixture: Dictionary = row.case
			main.flippers.reset_input()
			main.flippers.swing_angle = 18.0
			main.flippers.raise_speed = 600.0
			main.flippers.return_speed = 420.0
			main.flippers.pass_until_descending = true
			if fixture.angle != 0.0:
				main.flippers.advance(float(fixture.angle) / 600.0, true, true)
			for item: PinballFlipper in main.flippers.items:
				item.angular_velocity = 0.0
				item.collision_layer = 8 << item.side
			var target: PinballFlipper = main.flippers.items[int(fixture.side)]
			var rising: bool = fixture.angle == 0.0
			var plan := target.plan_motion(rising, 18.0, 600.0 if rising else 420.0)
			var duration: float = 1.0 / fixture.rate
			main.flippers.advance(duration, rising, rising)
			main.ball.radius = float(fixture.radius)
			main.ball.gravity = 0.0
			main.ball.max_speed = 3600.0
			main.ball.hit_sound = null
			main.ball.collision_mask = 8 << target.side
			main.ball.reset_at(_vector(fixture.start), _vector(fixture.velocity))
			main.ball.advance(duration, [plan])
			results.append({"mode": mode, "id": id, "rate": row.rate,
				"position": [main.ball.global_position.x, main.ball.global_position.y],
				"velocity": [main.ball.velocity.x, main.ball.velocity.y],
				"exceptions": main.ball.get_collision_exceptions().size()})
	preview.set_mode(3)
	var output := {"controls": controls, "results": results,
		"scope": "Live rendered preview; actual four-mode key handlers and lean motion; two CLI fixtures per mode"}
	var file := FileAccess.open("res://experiments/flippers/evidence/separation_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	return output


func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
