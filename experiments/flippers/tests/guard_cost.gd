extends SceneTree

const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Audit = preload("res://experiments/flippers/tests/guard_audit.gd")
const Trace = preload("res://experiments/flippers/tests/guard_trace.gd")
const ExitGuard = preload("res://experiments/flippers/tests/guard_exit.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(main, 2)
	root.add_child(main)
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.spawner.enabled = false
	Audit.install_manager(main, false)
	await physics_frame
	await physics_frame
	var manager := main.flippers as ExitGuard
	var trace := Trace.new(main.ball)
	trace.flippers = manager
	trace.radius = 24.0
	trace._source_plans = manager.plan_motion(true, true)
	manager.sampled_id = main.ball.get_instance_id()
	var rows: Array[Dictionary] = []
	for position: Vector2 in [Vector2(800, 900), Vector2(800, 1040)]:
		main.ball.global_position = position
		for method: String in ["current_refresh", "reused_geometry", "extra_geometry", "external_two_gaps"]:
			var samples: Array[float] = []
			manager.initial_contacts.clear()
			for item: PinballFlipper in manager.items:
				manager.initial_contacts[item.get_instance_id()] = not item._contact_at(
					position, 24.0, item.global_transform, 0.0, 0.0).is_empty()
			manager.early_exit = method != "current_refresh"
			for batch: int in 10:
				var start := Time.get_ticks_usec()
				for repeat: int in 200:
					manager._passing_targets[manager.sampled_id] = true
					if method == "extra_geometry":
						for item: PinballFlipper in manager.items:
							manager.initial_contacts[item.get_instance_id()] = not item._contact_at(
								position, 24.0, item.global_transform, 0.0, 0.0).is_empty()
					if method == "external_two_gaps": trace._gaps(position, .008)
					else: manager.refresh_target(main.ball, -1500)
				if batch > 0: samples.append(float(Time.get_ticks_usec() - start) / 200.0)
			rows.append({"position": [position.x, position.y], "method": method, "batch_mean_us": samples})
	main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/guard_cost.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": rows,
		"scope": "Component cost only; one warmup and nine batches of 200 calls; no observer, full motion, Enemy or rendering"}))
	quit(0)
