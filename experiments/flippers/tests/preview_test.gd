extends SceneTree

const Preview = preload("res://experiments/flippers/preview.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var original := load("res://main/main.tscn").instantiate() as PinballLab
	root.add_child(original)
	original.set_physics_process(false)
	original.spawner.enabled = false
	var preview := load("res://experiments/flippers/preview.tscn").instantiate() as Preview
	root.add_child(preview)
	preview.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not preview.paused, "Preview must start playing")
	preview.set_paused(true)
	for path: String in ["Playfield/Boundary", "Playfield/Ball",
		"Playfield/Flippers/LeftFlipper", "Playfield/Flippers/RightFlipper"]:
		var expected := original.get_node(path) as Node2D
		var actual := preview.get_node(path) as Node2D
		_check(expected.global_position.is_equal_approx(actual.global_position), "Layout differs: " + path)
	_check(preview.boundary.opening_width == original.boundary.opening_width, "Drain width differs")
	_check(preview.flippers.swing_angle == original.flippers.swing_angle, "Swing angle differs")
	for path: String in ["EnemySpawner", "Enemies", "Routes", "CrowdManager", "WorldSoundOutput",
		"PostProcessing", "Playfield/Bumper", "Playfield/MissileLauncher", "Playfield/DebugSummon"]:
		_check(preview.get_node_or_null(path) == null, "Unneeded main component remains: " + path)
	# The original and preview share a world in this test; keep the original out of native queries.
	for body: Node in original.find_children("*", "CollisionObject2D", true, false):
		(body as CollisionObject2D).collision_layer = 0
	for hand in 2:
		var flipper := preview.flippers.items[hand] as FixedFlipper
		_check(flipper.pivot_socket == preview.boundary.get_node("LeftPivot" if hand == 0 else "RightPivot"),
			"Preview uses a test socket instead of the main socket")
		for radius: float in [6.0, 24.0, 36.0]:
			for degrees in range(0, 19, 3):
				var angle := flipper._rest_rotation + flipper._direction * deg_to_rad(degrees)
				var pose := Transform2D(angle, flipper.global_position)
				var points := flipper.world_polygon_at(pose)
				_check(points[0].x == flipper.fixed_left and points[1].x == flipper.fixed_right,
					"Fixed horizontal bounds moved")
				_check(points[2].y == flipper.fixed_bottom and points[3].y == flipper.fixed_bottom,
					"Fixed bottom moved")
				var omega := flipper._direction * deg_to_rad(600.0)
				for edge in [1, 2, 3]:
					var a := points[edge]
					var b := points[(edge + 1) % 4]
					var tangent := b - a
					var normal := Vector2(tangent.y, -tangent.x).normalized()
					var center := a.lerp(b, 0.5) + normal * (radius - 0.5)
					var hit := flipper._contact_at(center, radius, pose, omega, 0.5)
					_check(not hit.is_empty(), "Fixed face contact missing")
					if not hit.is_empty():
						_check((hit.surface_velocity as Vector2).is_zero_approx(), "Fixed face has velocity")
						_check(not hit.is_striking and not hit.on_shot_face, "Fixed face grants a shot")
				var top := points[0].lerp(points[1], 0.5)
				var normal := pose.basis_xform(Vector2(0.0, flipper._direction)).normalized()
				var hit := flipper._contact_at(top + normal * (radius - 0.5), radius, pose, omega, 0.5)
				_check(not hit.is_empty(), "Moving upper face contact missing")
				if not hit.is_empty():
					var physical := PinballFlipper._point_velocity(top - pose.origin,
						pose * flipper._tip.position - pose.origin, omega, 0.0)
					_check(absf((hit.surface_velocity as Vector2).dot(normal) - physical.dot(normal)) < 0.01,
						"Upper normal speed changed")
				var embedded := top - normal * radius * 0.5
				var distance := flipper.upward_separation(embedded, radius, pose)
				_check(flipper._contact_at(embedded + Vector2.UP * distance,
					radius, pose, 0.0, 0.0).is_empty(), "Upward separation failed")
	# Reproduce clicking the pause button before using Space, which used to activate focused buttons.
	preview.reset_ball()
	var pause_button := preview.get_node("PreviewControls").find_child("Pause", true, false) as Button
	var reset_button := preview.get_node("PreviewControls").find_child("Reset", true, false) as Button
	_check(pause_button.focus_mode == Control.FOCUS_NONE, "Pause button accepts keyboard focus")
	_check(reset_button.focus_mode == Control.FOCUS_NONE, "Reset button accepts keyboard focus")
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = pause_button.get_global_rect().get_center()
		click.pressed = pressed
		root.push_input(click, true)
	await physics_frame
	_check(not preview.paused, "Mouse click did not resume the preview")
	_send_key(KEY_SPACE, true)
	await physics_frame
	_check(not preview.paused, "Space changed pause state after a mouse click")
	_check(Input.is_action_pressed(&"pinball_left") and Input.is_action_pressed(&"pinball_right"),
		"Space does not operate both flippers")
	var rest_angles: Array[float] = [preview.flippers.items[0].rotation, preview.flippers.items[1].rotation]
	preview.advance(1.0 / 60.0)
	_check(preview.flippers.items[0].rotation != rest_angles[0] and
		preview.flippers.items[1].rotation != rest_angles[1], "Space did not move both flippers")
	_send_key(KEY_SPACE, false)
	_send_key(KEY_P, true)
	_send_key(KEY_P, false)
	await physics_frame
	_check(preview.paused, "P did not pause the preview")
	_send_key(KEY_SPACE, true)
	_send_key(KEY_SPACE, false)
	await physics_frame
	_check(preview.paused, "Space resumed a paused preview")
	for frame in 120:
		preview.advance(1.0 / 60.0)
		await physics_frame
	_check(is_finite(preview.ball.global_position.x) and is_finite(preview.ball.velocity.y),
		"Ball state is invalid")
	preview.reset_ball()
	_check(preview.ball.global_position.is_equal_approx(original.ball.global_position), "Reset layout differs")
	print("Preview checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _send_key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures < 12:
			push_error(message)
