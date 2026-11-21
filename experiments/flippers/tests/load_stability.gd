extends SceneTree

const World = preload("res://experiments/flippers/tests/load_world.gd")
const Motion = preload("res://experiments/flippers/tests/load_motion.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var results: Array[Dictionary] = []
	for count: int in [30, 60]:
		for mode: int in [0, 4]:
			var world := World.new()
			root.add_child(world)
			world.setup({"balls": 1, "enemies": count, "moving": true}, mode == 4, true)
			for attempt in 300:
				await physics_frame
				if not world.main.routes.path_from(Vector2(800, 200), 30.0).is_empty():
					break
			world.settle_balls()
			await physics_frame
			assert(world.populate(), "Stability population failed")
			await physics_frame
			for frame in 60:
				world.tick(1.0 / 60.0, frame)
				await physics_frame
			world.reset_episode()
			await physics_frame
			assert(world.populate(), "Stability reset failed")
			await physics_frame
			var caps: Array[Dictionary] = []
			var maximum := {"distance": 0.0}
			for frame in 240:
				var update := world.tick(1.0 / 60.0, frame)
				var motion := world.main.ball._motion as Motion
				if motion.discarded_seconds > 0.0:
					caps.append({"frame": frame, "enemies": update.enemies_start,
						"discarded_us": update.discarded_us, "events": motion.events.duplicate(true)})
				for event: Dictionary in motion.events:
					if event.correction_px > maximum.distance:
						maximum = {"distance": event.correction_px, "frame": frame, "event": event.duplicate(true)}
				await physics_frame
			results.append({"initial_enemies": count, "mode": mode, "caps": caps,
				"max_correction": maximum, "outcome": world.outcome()})
			for player: AudioStreamPlayer2D in world.main._sound._players:
				player.stop()
				player.stream = null
			world.main._sound._pending_aggregations.clear()
			world.free()
			# Let the audio mixer release the stopped playback outside the measured replay.
			OS.delay_msec(30)
	var file := FileAccess.open("res://experiments/flippers/evidence/load_stability.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": results, "physics_hz": 60,
		"automatic_updates_disabled": true,
		"scope": "Focused diagnostic replay, not a performance sample"}, "\t"))
	print("Load stability replays: ", results.size())
	quit(0)
