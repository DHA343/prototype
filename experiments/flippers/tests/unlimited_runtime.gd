extends RefCounted


func run(preview: Node) -> Dictionary:
	var output: Array[Dictionary] = []
	var controls: Array[Dictionary] = []
	for mode: int in 3:
		for preset: int in 4:
			var key := InputEventKey.new()
			key.pressed = true
			key.keycode = KEY_1 + mode
			preview._unhandled_key_input(key)
			controls.append({"mode": mode, "label": str(preview.label.text),
				"distance_limited": preview.main.ball._motion.recovery.distance_limited})
			key.keycode = KEY_4 + preset
			preview._unhandled_key_input(key)
			while preview.replaying:
				await preview.get_tree().physics_frame
			var ball: PinballBall = preview.main.ball
			output.append({"mode": mode, "preset": preset, "frames": int(preview.frames),
				"position": [ball.global_position.x, ball.global_position.y],
				"velocity": [ball.velocity.x, ball.velocity.y],
				"max_correction_px": float(preview.max_correction),
				"caps": int(preview.capped_updates), "unresolved": ball._motion.recovery.failed,
				"label": str(preview.label.text)})
	preview.set_mode(2)
	preview.replay(3)
	preview.replay_paused = true
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_N
	preview._unhandled_key_input(key)
	var stepped: bool = preview.frames == 1
	var file := FileAccess.open("res://experiments/flippers/evidence/unlimited_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": output, "controls": controls,
		"single_step": stepped, "scope": "Rendered physics replay of four presets in three modes"}, "\t"))
	return {"cases": output.size(), "single_step": stepped}
