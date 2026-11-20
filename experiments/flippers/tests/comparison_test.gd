extends SceneTree

const Comparison = preload("res://experiments/flippers/comparison.gd")
const Guard = preload("res://experiments/flippers/shot_guard.gd")
const Preview = preload("res://experiments/flippers/preview.gd")
const PreviewBall = preload("res://experiments/flippers/preview_ball.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var comparison := load("res://experiments/flippers/comparison.tscn").instantiate() as Comparison
	root.add_child(comparison)
	comparison.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(not comparison.paused, "Comparison does not start playing")
	_check(comparison.previews[0].ball.get_world_2d() != comparison.previews[1].ball.get_world_2d(),
		"Comparison worlds are shared")
	for index in 2:
		var preview := comparison.previews[index]
		var guard := preview.flippers as Guard
		_check(guard.mode == index, "Wrong mode")
		_check(preview.get_node_or_null("PreviewControls") == null, "Duplicate controls remain")
		_check(preview.ball.global_position == Vector2(780, 540), "Main spawn changed")
		_check(guard._states.is_empty(), "Ball starts suppressed")

	# Actual powered hit, not a synthetic flag: one shot must start the guard.
	comparison.replay_tip_shot()
	for frame in 12:
		comparison.advance(1.0 / 60.0)
		await physics_frame
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		_check(guard.shot_count == 1, "Reproduction did not make exactly one powered shot")
		_check(preview.ball.get_collision_exceptions().is_empty(), "Temporary exceptions leaked")
	print("Tip replay at 200 ms: ", _snapshot(comparison))
	_check((comparison.previews[0].flippers as Guard).is_suppressed(comparison.previews[0].ball),
		"Ascending shot lost its suppression")
	_check(not (comparison.previews[1].flippers as Guard).is_suppressed(comparison.previews[1].ball),
		"Timer did not expire")

	# The opposite flipper is already raised: reproduce different input timings,
	# rather than assuming the two flippers always start at the same angle.
	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		guard.duration_ms = 5.0
		guard.advance(guard.swing_angle / guard.raise_speed, false, true)
		var left := guard.items[0] as FixedFlipper
		var points := left.world_polygon_at(left.global_transform)
		var top := points[0].lerp(points[1], 0.92)
		preview.ball.reset_at(top + Vector2.UP * (preview.ball.radius + 4.0), Vector2(0, 300))
	for frame in 12:
		for preview: Preview in comparison.previews:
			preview.advance_inputs(1.0 / 60.0, true, true)
		await physics_frame
	print("Opposite already raised, 5 ms: ", _snapshot(comparison))
	for preview: Preview in comparison.previews:
		_check((preview.flippers as Guard).shot_count == 1, "Asynchronous input changed powered shot count")

	# An upward ball that has not been shot must remain eligible for contact.
	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		preview.ball.velocity = Vector2(0, -500)
		guard.begin_step(preview.ball, Preview.STEP)
		_check(not guard.is_suppressed(preview.ball), "Unshot upward ball is suppressed")
		guard.finish_step(preview.ball, Preview.STEP)

	# A second ball using the same manager must not inherit another ball's state.
	var first := comparison.previews[0]
	var first_guard := first.flippers as Guard
	var second_ball := first.ball.duplicate() as PreviewBall
	first.ball.get_parent().add_child(second_ball)
	second_ball.flippers = first_guard
	second_ball.boundary = first.boundary
	first_guard.record_shot(first.ball, 0.0)
	_check(not first_guard.is_suppressed(second_ball), "Other ball inherited suppression")
	first_guard.record_shot(second_ball, 0.0)
	second_ball.free()
	_check(first_guard._states.size() == 1, "Removed ball's guard state remains")

	# Traverse the opposite flipper from below. This checks BOTH native stopped
	# bodies and the custom rotating sweep, including absence of upward correction.
	for moving: bool in [false, true]:
		comparison.reset_balls()
		for preview: Preview in comparison.previews:
			var guard := preview.flippers as Guard
			guard.duration_ms = 150.0
			var right := guard.items[1] as FixedFlipper
			var points := right.world_polygon_at(right.global_transform)
			var start := Vector2(lerpf(right.fixed_left, right.fixed_right, 0.25),
				right.fixed_bottom + preview.ball.radius + 2.0)
			preview.ball.reset_at(start, Vector2(0, -1800))
			guard.record_shot(preview.ball, 0.0)
			for frame in 5:
				preview.advance_inputs(1.0 / 60.0, false, moving)
				await physics_frame
			_check(preview.ball.velocity.y < -1500.0, "Suppressed ball was reflected")
			_check(preview.ball.max_separation == 0.0, "Suppressed ball was pushed upward")
			_check(preview.ball.global_position.y < points[0].lerp(points[1], 0.25).y,
				"Suppressed ball was blocked by a flipper")
			_check(preview.ball.get_collision_exceptions().is_empty(), "Exceptions leaked after passage")

	# Descending return re-enables contact immediately, in both modes, before timeout.
	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		guard.duration_ms = 150.0
		var right := guard.items[1] as FixedFlipper
		var points := right.world_polygon_at(right.global_transform)
		var top := points[0].lerp(points[1], 0.4)
		preview.ball.reset_at(top + Vector2.UP * (preview.ball.radius + 2.0), Vector2(0, 500))
		guard.record_shot(preview.ball, 0.0)
		preview.advance_inputs(1.0 / 60.0, false, false)
		await physics_frame
		_check(not guard.is_suppressed(preview.ball), "Descending return is still suppressed")
		_check(guard.descent_releases == 1, "Descent release not recorded")
		_check(preview.ball.velocity.y < 0.0, "Descending return was not caught")

	# Timer expiration while still ascending: only mode 4 accepts the next contact.
	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		guard.duration_ms = 5.0
		preview.ball.velocity = Vector2(0, -600)
		guard.record_shot(preview.ball, 0.0)
		for step in 3:
			guard.begin_step(preview.ball, Preview.STEP)
			guard.finish_step(preview.ball, Preview.STEP)
		_check(guard.is_suppressed(preview.ball) == (guard.mode == Guard.Mode.UNTIL_DESCENDING),
			"Expiry rule differs from the chosen mode")

	# Stress the known boundary: timeout occurs while the ball is still inside
	# the thick body. This is not a claim that overlap recovery is visually ideal.
	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		guard.duration_ms = 5.0
		var right := guard.items[1] as FixedFlipper
		var points := right.world_polygon_at(right.global_transform)
		var top := points[0].lerp(points[1], 0.35)
		var start := top + Vector2.DOWN * 30.0
		preview.ball.reset_at(start, Vector2(0, -600))
		guard.record_shot(preview.ball, 0.0)
		for frame in 6:
			preview.advance_inputs(1.0 / 60.0, false, true)
			await physics_frame
		_check(is_finite(preview.ball.global_position.y), "Timeout overlap produced invalid position")
		_check(preview.ball.global_position.distance_to(start) > 10.0, "Timeout overlap stopped all movement")
	print("Expiry inside thick body: ", _snapshot(comparison))

	comparison.reset_balls()
	for preview: Preview in comparison.previews:
		_check((preview.flippers as Guard)._states.is_empty(), "Reset retains suppression")
	comparison.set_paused(true)
	_check(comparison._duration_field.editable, "Paused duration field is disabled")
	# Mouse pause-button focus must never turn Space into a pause command.
	var pause_button := comparison._pause_button
	for pressed: bool in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = pause_button.get_global_rect().get_center()
		click.pressed = pressed
		root.push_input(click, true)
	await physics_frame
	_check(not comparison.paused, "Pause button did not resume comparison")
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.pressed = true
	Input.parse_input_event(space)
	await physics_frame
	comparison.advance(1.0 / 60.0)
	_check(not comparison.paused, "Space changed pause state")
	for preview: Preview in comparison.previews:
		_check(absf(preview.flippers.items[0]._offset) > 0.0
			and absf(preview.flippers.items[1]._offset) > 0.0, "Space did not move both flippers")
	space.pressed = false
	Input.parse_input_event(space)
	await physics_frame
	print("Comparison checks: ", checks, "; failures: ", failures)
	comparison.free()
	quit(0 if failures == 0 else 1)


func _snapshot(comparison: Comparison) -> Array:
	var result: Array = []
	for preview: Preview in comparison.previews:
		var guard := preview.flippers as Guard
		result.append({"mode": guard.mode, "shots": guard.shot_count,
			"suppressed": guard.is_suppressed(preview.ball), "time_releases": guard.time_releases,
			"position": preview.ball.global_position, "velocity": preview.ball.velocity})
	return result


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
