extends SceneTree

const ContactPreview = preload("res://experiments/flippers/contact_preview.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load("res://experiments/flippers/contact_preview.tscn").instantiate() as ContactPreview
	root.add_child(scene)
	scene.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not scene.paused, "Contact preview must start playing")
	scene.set_paused(true)
	scene.advance(1.0 / 60.0)
	for preview: Node2D in scene.previews:
		_check(preview.ball.updates == 1, "Unexpected global subdivision")
	for index in 3:
		scene.replay_case(index)
		await physics_frame
		scene.advance(1.0 / 60.0)
		print("Replay ", index, ": ", scene.previews[0].ball.shots, "/", scene.previews[1].ball.shots,
			"; velocity ", scene.previews[0].ball.velocity, "/", scene.previews[1].ball.velocity)
		_check(scene.paused, "Replay did not stop after one update")
		_check(scene.previews[0].ball.shots == 1, "Frozen-pose false shot not reproduced")
		_check(scene.previews[1].ball.shots == (1 if index == 2 else 0),
			"Simultaneous-time method made a wrong shot")
		if index == 0:
			_check(scene.previews[1].ball.velocity.distance_to(Vector2(0, -600)) < 0.01,
				"Non-contact path changed velocity")
			_check(absf(scene.previews[0].ball.velocity.x - 525.805) < 0.1,
				"Replay differs from audited first response")
		if index == 2:
			_check(scene.previews[0].ball.global_position.distance_to(scene.previews[1].ball.global_position) > 35,
				"Large position correction was not reproduced")
	scene.set_ball_count(20)
	for index in 2:
		for target: Node in scene.previews[index].balls:
			_check(target.rotation_sweep == (index == 1), "Cloned ball has wrong detector")
			_check(target.iterative and target.guard_enabled and not target.final_response,
				"Common response mode changed")
	scene.free()
	print("Contact preview checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
