extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check(DirAccess.make_dir_recursive_absolute("res://_temp") == OK, "Preview directory exists")
	var scene := load("res://main/main.tscn") as PackedScene
	var main := scene.instantiate() as PinballLab
	root.add_child(main)
	current_scene = main
	main.set_physics_process(false)
	var field := main.get_node("Playfield") as PixelationLayer
	var post := main.get_node("PostProcessing") as PostProcessing
	for size: Vector2i in [Vector2i(640, 360), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = size
		await _draw_frames()
		var output := root.get_texture().get_image()
		var scale := float(size.x) / 1920.0
		_check(output.get_size() == size, "Output size")
		_check(field.get_node("Source").size == Vector2i(640, 360), "Fixed 640x360 playfield")
		_check(not post.enabled, "No decorative post-processing by default")
		for side: int in 2:
			var connection := main.boundary.connection_position(side)
			for ratio: float in [0.35, 0.5, 0.65]:
				var point := main.boundary.to_global(Vector2(connection.x, connection.y * ratio))
				_check(_brightness(output, point * scale, scale * 6.0) > 0.1,
					"Side boundary stays vertical")
		var top := main.boundary.to_global(Vector2.ZERO)
		_check(_brightness(output, top * scale, scale * 6.0) > 0.1, "Upper wall is visible")
		for side: float in [-1.0, 1.0]:
			var vertex := main.boundary.to_global(Vector2(side * main.boundary.width * 0.5, 0.0))
			_check(_brightness(output, vertex * scale, scale * 3.0) < 0.08, "Upper sharp vertex is cut away")
		for side: int in 2:
			var point := main.boundary.to_global(main.boundary.sample_interval(0.5, side))
			_check(_brightness(output, point * scale, scale * 6.0) > 0.2,
				"Flipper interval is visible on the straight lower edge")
			for ratio: float in [0.0, 0.5, 1.0]:
				var sample := main.boundary.to_global(main.boundary.sample_interval(ratio, side))
				var direction := Vector2.UP
				_check(_brightness(output, (sample + direction * 36.0) * scale, scale * 3.0) < 0.08,
					"No unsolicited direction lines extend from the flipper")
		if size == Vector2i(1280, 720):
			_check(output.save_png("res://_temp/pinball_flippers_rest.png") == OK, "Preview saves")

	root.size = Vector2i(1280, 720)
	# A small authored swing can still overlap the resting line with a solid body.
	# Use a larger test swing to check that no stationary duplicate remains.
	var swing_angle := main.flippers.swing_angle
	main.flippers.swing_angle = maxf(30.0, swing_angle)
	main.flippers.advance(0.5, true, true)
	main.flippers.advance(0.1, true, true)
	await _draw_frames()
	var raised := root.get_texture().get_image()
	for side: int in 2:
		var flipper := main.flippers.items[side]
		var midpoint := flipper.root_surface_position().lerp(flipper.tip_position(), 0.5)
		_check(_brightness(raised, midpoint * (2.0 / 3.0), 3.0) > 0.2, "Blue segment follows raised collision")
		var old_midpoint := main.boundary.to_global(main.boundary.sample_interval(0.5, side))
		_check(_brightness(raised, old_midpoint * (2.0 / 3.0), 2.0) < 0.08, "Resting segment disappears when raised")
	_check(raised.save_png("res://_temp/pinball_flippers_raised.png") == OK, "Raised preview saves")
	main.flippers.advance(0.5, false, false)
	main.flippers.swing_angle = swing_angle
	post.enabled = true
	await _draw_frames()
	_check(root.get_texture().get_image().save_png("res://_temp/pinball_optional_crt.png") == OK,
		"Migrated effects remain available")
	post.enabled = false
	await _draw_frames()
	await _test_shot_guide(main)
	for failure: String in _failures:
		printerr("FAIL: " + failure)
	print("Render failures: ", _failures.size())
	main.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _test_shot_guide(main: PinballLab) -> void:
	main.reset_ball()
	var table := main.flippers.items[0] as TableFlipper
	var points := table.world_polygon_at(table.global_transform)
	var normal := (points[1] - points[0]).orthogonal().normalized()
	var ball := main.ball
	main.place_ball(points[0].lerp(points[1], 0.55) + normal * (ball.radius + 1.0),
		-normal * 300.0)
	var predicted := main.predict_shot()
	_check(predicted != Vector2.ZERO, "Directed shot has a visible guide")
	if predicted == Vector2.ZERO:
		return
	await _draw_frames()
	var sample := (ball.global_position + predicted.normalized() * 100.0) * (2.0 / 3.0)
	var visible := _brightness(root.get_texture().get_image(), sample, 4.0)
	main.flippers.disable_target(ball)
	await _draw_frames()
	var hidden := _brightness(root.get_texture().get_image(), sample, 4.0)
	_check(visible > hidden + 0.12, "Guide pixels disappear when guard 3 disables the shot")


func _draw_frames() -> void:
	for _frame in 6:
		await process_frame
	await RenderingServer.frame_post_draw


func _brightness(output: Image, point: Vector2, radius: float) -> float:
	var brightest := 0.0
	for y in range(maxi(0, int(point.y - radius)), mini(output.get_height(), int(point.y + radius) + 1)):
		for x in range(maxi(0, int(point.x - radius)), mini(output.get_width(), int(point.x + radius) + 1)):
			brightest = maxf(brightest, output.get_pixel(x, y).get_luminance())
	return brightest


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
