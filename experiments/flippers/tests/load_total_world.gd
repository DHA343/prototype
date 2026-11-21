extends "res://experiments/flippers/tests/load_world.gd"


func tick(delta: float, frame: int) -> Dictionary:
	var left: bool = config.moving and fmod(frame * delta, 0.55) < 0.08
	var right: bool = config.moving and fmod(frame * delta + 0.275, 0.55) < 0.08
	_set_input(&"pinball_left", left)
	_set_input(&"pinball_right", right)
	if balls.is_empty():
		main._respawn_remaining = INF
	var before := main.enemies.size()
	var began := Time.get_ticks_usec()
	if balls.size() > 1:
		_multiball_tick(delta, left, right)
	else:
		main.advance(delta)
	guide.set("_shot_velocity", main.predict_shot())
	guide.queue_redraw()
	var elapsed := Time.get_ticks_usec() - began
	return {"app_us": elapsed, "enemies_start": before, "enemies_end": main.enemies.size(),
		"missiles": main.launcher._flights.size(), "killed": removed.killed, "escaped": removed.escaped}


func _multiball_tick(delta: float, left: bool, right: bool) -> void:
	main.routes.refresh()
	var plans := main.flippers.plan_motion(left, right)
	main.flippers.advance(delta, left, right)
	for enemy: Enemy in main.enemies:
		enemy.prepare(delta)
	main.crowd.calculate(main.enemies, delta, main.boundary.exit_target())
	for enemy: Enemy in main.enemies:
		enemy.advance(delta)
	for index in balls.size():
		var ball := balls[index]
		if ball.active:
			ball.advance(delta, plans)
			if main.boundary.to_local(ball.global_position).y > main.boundary.bottom + 120.0:
				ball.active = false
				ball.visible = false
				respawns[index] = main.respawn_delay
		else:
			respawns[index] -= delta
			if respawns[index] <= 0.0:
				if index == 0:
					main.flippers.reset_input()
				ball.reset_at(starts[index])
	for index in range(main.enemies.size() - 1, -1, -1):
		var enemy := main.enemies[index]
		if main.boundary.has_exited(enemy.global_position, enemy.radius):
			enemy.finish(Enemy.ExitReason.ESCAPED)
	main.spawner.advance(delta)
	main.launcher.advance(delta, main.enemies)


func _exit_tree() -> void:
	Input.action_release(&"pinball_left")
	Input.action_release(&"pinball_right")


func _set_input(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)
