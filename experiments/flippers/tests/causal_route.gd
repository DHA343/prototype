extends "res://experiments/flippers/tests/causal_audit.gd"


func _run() -> void:
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var actor := _new_enemy(Vector2(960, 120), true)
	(actor as CausalEnemy).trace_enabled = false
	var actors: Array[Enemy] = [actor]
	var output := {"speed": actor.move_speed, "at_20s": {}, "exit_s": null,
		"scope": "Original Enemy.advance, actual routes/crowd, one enemy, no ball movement, no parameter changes"}
	for frame: int in 3600:
		_main.routes.refresh()
		_main.flippers.advance(1.0 / 60.0, false, false)
		actor.prepare(1.0 / 60.0)
		_main.crowd.calculate(actors, 1.0 / 60.0, _main.boundary.exit_target())
		actor.advance(1.0 / 60.0)
		if frame == 1199:
			output.at_20s = {"position": _vec(actor.global_position), "velocity": _vec(actor.velocity)}
		if _main.boundary.has_exited(actor.global_position, actor.radius):
			output.exit_s = float(frame + 1) / 60.0
			break
		await physics_frame
	var source: Node = load("res://main/main.tscn").instantiate()
	var ball := source.get_node("Playfield/Ball") as PinballBall
	var flipper := source.get_node("Playfield/Flippers/LeftFlipper") as PinballFlipper
	output["scene_layers"] = {"ball_layer": ball.collision_layer, "ball_mask": ball.collision_mask,
		"flipper_layer": flipper.collision_layer, "flipper_mask": flipper.collision_mask,
		"enemy_layer": actor.collision_layer, "enemy_mask": actor.collision_mask}
	source.free()
	actor.free()
	_main.free()
	_write("causal_route.json", output)
	print("Causal route observation: ", output)
	quit(0)
