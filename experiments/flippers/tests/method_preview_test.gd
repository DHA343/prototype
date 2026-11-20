extends SceneTree

const MethodPreview = preload("res://experiments/flippers/method_preview.gd")
const MatrixBall = preload("res://experiments/flippers/tests/matrix_ball.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var scene := load("res://experiments/flippers/method_preview.tscn").instantiate() as MethodPreview
	root.add_child(scene)
	scene.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not scene.paused, "Method preview does not start playing")
	scene.set_paused(true)
	scene.reset_balls()
	scene.advance(1.0 / 60.0)
	_check(scene.previews[0].ball.updates == 4, "Legacy subdivision is missing")
	_check(scene.previews[1].ball.updates == 1, "Candidate still subdivides body updates")
	scene.set_ball_count(20)
	for index in 2:
		var preview := scene.previews[index]
		_check(preview.balls.size() == 20, "Wrong ball count")
		_check(preview.flippers.mode == 0, "Guard modes differ")
		for target: PinballBall in preview.balls:
			var ball := target as MatrixBall
			_check(ball != null and ball.iterative == (index == 0), "Duplicated ball has wrong response mode")
			_check(ball.rotation_sweep and ball.guard_enabled, "Common contact settings differ")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await physics_frame
	scene.advance(1.0 / 60.0)
	_check(scene.paused, "Space changed pause state")
	for preview: Node2D in scene.previews:
		_check(absf(preview.flippers.items[0]._offset) > 0, "Flippers did not move")
	space.pressed = false
	Input.parse_input_event(space)
	scene.set_ball_count(1)
	_check(scene.previews[0].balls.size() == 1 and scene.previews[1].balls.size() == 1,
		"Ball count reduction failed")
	_check(scene.previews[1].ball.updates == 0, "Reset retains update counter")
	scene.free()
	print("Method preview checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
