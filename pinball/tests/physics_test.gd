extends SceneTree

const TEST_STEP: float = 1.0 / 240.0

const MAIN: PackedScene = preload("res://main/main.tscn")

var _main: PinballLab
var _boundary: PinballBoundary
var _ball: PinballBall
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = MAIN.instantiate() as PinballLab
	(_main.get_node("EnemySpawner") as EnemySpawner).enabled = false
	# Physics assertions do not need playback or audio-thread teardown.
	var layout := Node2D.new()
	layout.name = "Layout"
	var obstacles := Node2D.new()
	obstacles.name = "Obstacles"
	_main.get_node("Playfield").add_child(layout)
	layout.owner = _main
	layout.add_child(obstacles)
	obstacles.owner = _main
	for child: Node in _main.get_node("Playfield").find_children("*", "", true, false):
		if child is PinballBumper:
			child.hit_sound = null
			child.owner = null
			child.reparent(obstacles, false)
			child.name = "Obstacle" + str(obstacles.get_child_count())
			child.owner = _main
	root.add_child(_main)
	_main.set_physics_process(false)
	_boundary = _main.boundary
	_ball = _main.ball
	await physics_frame
	await physics_frame
	for child: Node in obstacles.get_children():
		var bumper := child as PinballBumper
		_check(bumper.hit_occurred.is_connected(_main._on_bumper_hit.bind(bumper)),
			"Renamed nested bumpers connect their hit notifications")
	_test_bumper_missiles(obstacles.get_child(0) as PinballBumper)
	_test_swept_tip()
	await _test_solid_flippers()
	await _test_authoring()
	await _test_sockets()
	await _test_bottom_anchor()
	await _test_setting_independence()
	await _test_slider_updates()
	await _test_sides_and_top()
	await _test_rounded_corners()
	await _test_lower_contacts()
	await _test_connections()
	await _test_strikes()
	await _test_power_equalization()
	await _test_bumper_and_respawn()
	await _test_layout()
	for failure: String in _failures:
		printerr("FAIL: " + failure)
	print("Pinball checks: %d; failures: %d" % [_checks, _failures.size()])
	_main.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _test_swept_tip() -> void:
	var gravity := _ball.gravity
	_ball.gravity = 0.0
	# This trajectory crosses the rising tip during the step and clears its final pose.
	var shape := _main.flippers.items[0] as TableFlipper
	var polygon := shape.world_polygon_at(shape.global_transform)
	_main.place_ball(polygon[0].lerp(polygon[1], 0.95) + Vector2(-42, -(_ball.radius + 12)),
		Vector2(3600, 600))
	var predicted := _main.predict_shot()
	Input.action_press(&"pinball_left")
	_main.advance(TEST_STEP)
	Input.action_release(&"pinball_left")
	_check(_ball.last_normal != Vector2.ZERO and _ball.velocity.y < 0.0,
		"Main detects a high-speed contact with the tip during its rotation")
	_check(_ball.velocity.is_equal_approx(predicted), "Shot guide matches the swept tip strike")
	_main.reset_ball()
	_ball.gravity = gravity


func _test_solid_flippers() -> void:
	var gravity := _ball.gravity
	_ball.gravity = 0.0
	for widths: Vector2 in [Vector2(36.0, 18.0), Vector2(60.0, 30.0), Vector2(24.0, 12.0)]:
		_main.flippers.root_width = widths.x
		_main.flippers.tip_width = widths.y
		await _sync_layout()
		_main.flippers.reset_input()
		# The authored narrow drain must still pass the actual ball after a width edit.
		var center := _boundary.to_global(_boundary.opening_center)
		_main.place_ball(center + Vector2.UP * 90.0, Vector2.DOWN * 600.0)
		for _step in 96:
			_ball.advance(TEST_STEP)
		_check(_ball.global_position.y > center.y + 90.0,
			"Narrow drain remains traversable at root/tip widths %s" % widths)
		for flipper: PinballFlipper in _main.flippers.items:
			var middle := flipper.root_surface_position().lerp(flipper.tip_position(), 0.5)
			var normal := flipper.strike_normal()
			# Approach the solid underside; it must reflect without shot-power/direction bonuses.
			var underside := _ray(middle - normal * 120.0, middle + normal * 12.0)
			_check(not underside.is_empty() and underside["collider"] == flipper,
				"Thick flipper blocks the ball from its underside")
			if not underside.is_empty():
				var point: Vector2 = underside["position"]
				var outward: Vector2 = underside["normal"]
				_main.place_ball(point + outward * (_ball.radius + 0.5), -outward * 540.0)
				flipper.angular_velocity = -1.0 if flipper.side == 0 else 1.0
				var prediction := flipper.predicted_contact(point + outward * (_ball.radius - 0.1),
					_ball.radius, 0.00001, TEST_STEP, _main.flippers.swing_angle,
					_main.flippers.raise_speed, 1.0)
				_check(not prediction.is_empty(), "Prediction includes solid underside contact")
				if not prediction.is_empty():
					_check(not prediction["is_striking"], "Prediction does not grant underside shot bonuses")
				_check(not flipper.is_striking(point, outward), "Rising underside does not receive shot bonuses")
				var root_back := flipper.to_global(Vector2(-3.0, 0.0))
				_check(not flipper.is_striking(root_back, normal), "Wall-side root does not grant a powered shot")
				flipper.angular_velocity = 0.0
				for _step in 12:
					_ball.advance(TEST_STEP)
				_check(_ball.velocity.dot(outward) > 0.0, "Ball rebounds outward from the underside")
				flipper.angular_velocity = 0.0
			# The pivot position stays fixed through repeated raises and returns.
			var pivot := flipper.global_position
			for _cycle in 3:
				flipper.advance(0.1, true, 45.0, 720.0, 420.0)
				flipper.advance(0.2, false, 45.0, 720.0, 420.0)
			_check(flipper.global_position.is_equal_approx(pivot), "Round root rotates about its center")
		_main.flippers.reset_input()
	_main.flippers.root_width = 36.0
	_main.flippers.tip_width = 18.0
	_ball.gravity = gravity
	await _sync_layout()


func _test_authoring() -> void:
	_check(_main.get_node_or_null("Playfield/Table") == null, "One authored scene, no nested table")
	_check(not _main.get_node("PostProcessing").enabled, "Decorative effects start disabled")
	_boundary.width = 1500.0
	_boundary.height = 1080.0
	_boundary.opening_width = 360.0
	_boundary.opening_offset = Vector2(24.0, 144.0)
	_boundary.lower_angle = 12.0
	_boundary.upper_corner_radius = 54.0
	_boundary.lower_corner_radius = 90.0
	_boundary.start_distance = 270.0
	_boundary.opening_margin = 18.0
	_main.flippers.root_angle = -30.0
	_main.flippers.tip_angle = 50.0
	_main.flippers.power_equalization = 0.65
	await _sync_layout()
	var saved := PackedScene.new()
	_check(saved.pack(_main) == OK, "Complete lab packs as one scene")
	var path := "res://_temp/numeric_boundary_test.tscn"
	_check(ResourceSaver.save(saved, path) == OK, "Lab saves")
	var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored := loaded.instantiate()
	var boundary := restored.get_node("Playfield/Boundary") as PinballBoundary
	var motors := restored.get_node("Playfield/Flippers") as PinballFlippers
	for name: String in ["swing_angle", "raise_speed", "return_speed", "root_angle", "tip_angle",
		"power_equalization", "restitution", "root_width", "tip_width"]:
		_check(motors.get(name) == _main.flippers.get(name), name + " survives saving on Flippers")
	var left := motors.get_node("LeftFlipper") as PinballFlipper
	_check(left.pivot_socket == boundary.get_node("LeftPivot"), "Saved pivot socket reference is restored")
	_check(left.tip_socket == boundary.get_node("LeftTip"), "Saved tip socket reference is restored")
	for name: String in _setting_names():
		_check(boundary.get(name) == _boundary.get(name), name + " survives saving")
	_check(boundary.get_child_count(true) == 4, "Only authored sockets are serialized under Boundary")
	var computed_count := 0
	for property: Dictionary in boundary.get_property_list():
		if property.name in PinballBoundary.COMPUTED_PROPERTIES:
			computed_count += 1
			_check((int(property.usage) & PROPERTY_USAGE_READ_ONLY) != 0, "Computed value is read-only")
			_check((int(property.usage) & PROPERTY_USAGE_STORAGE) == 0, "Computed value is not stored")
	_check(computed_count == 8, "All derived measurements are visible in Inspector")
	_check(not FileAccess.get_file_as_string(path).contains("left_connection_y ="),
		"Saved scene contains inputs, not derived geometry")
	restored.free()
	_fixture()
	await _sync_layout()


func _test_sockets() -> void:
	_check(_boundary.find_children("*", "PinballFlipper", true, false).is_empty(),
		"Boundary does not own flippers")
	var boundary_transform := _boundary.transform
	var motor_transform := _main.flippers.transform
	_main.flippers.reset_input()
	_boundary.position += Vector2(51.0, -27.0)
	_boundary.rotation = 0.12
	_main.flippers.position = Vector2(-63.0, 39.0)
	_main.flippers.rotation = -0.08
	await _sync_layout()
	for flipper: PinballFlipper in _main.flippers.items:
		_check(flipper.root_surface_position().distance_to(flipper.pivot_socket.global_position) < 0.001,
			"Root contact surface follows wall sockets across different parent transforms")
		_check(flipper.tip_position().distance_to(flipper.tip_socket.global_position) < 0.001,
			"Resting tip follows wall sockets without a gap")
		var pivot := flipper.get_node("Pivot") as Marker2D
		var tip := flipper.get_node("Tip") as Marker2D
		var shape := (flipper.get_node("CollisionShape2D") as CollisionShape2D).shape as ConvexPolygonShape2D
		_check(shape.points.size() == 4, "Fixed-width solid collision is a quadrilateral")
		var expected := (flipper as TableFlipper).world_polygon_at(flipper.global_transform)
		for index in 4:
			_check(flipper.to_global(shape.points[index]).distance_to(expected[index]) < 0.001,
				"Native collision follows the fixed-width quadrilateral")
		_check(is_equal_approx(absf(tip.position.y), _main.flippers.root_width * 0.5),
			"Contact surface is offset from the center by the root radius")
	_main.flippers.position += Vector2(24.0, 15.0)
	await _sync_layout()
	_check(_main.flippers.items[0].root_surface_position().distance_to(
		_main.flippers.items[0].pivot_socket.global_position) < 0.001,
		"Moving the flipper parent preserves its socket attachment")
	var walls_restitution := _boundary.lower_restitution
	var flipper_restitution := _main.flippers.restitution
	_main.flippers.restitution = 0.75
	_check(_boundary.lower_restitution == walls_restitution, "Flipper restitution does not edit walls")
	_main.flippers.restitution = flipper_restitution
	_boundary.transform = boundary_transform
	_main.flippers.transform = motor_transform
	await _sync_layout()


func _test_bottom_anchor() -> void:
	var origin := _boundary.global_position
	_boundary.opening_offset = Vector2(0.0, 0.0)
	await _sync_layout()
	_check(is_equal_approx(_boundary.opening_edge(0).y, _boundary.height), "Zero offset places opening at lower edge")
	var previous := _boundary.opening_edge(0)
	_boundary.opening_offset.y = 120.0
	await _sync_layout()
	_check(_boundary.opening_edge(0).is_equal_approx(previous - Vector2(0.0, 120.0)),
		"Increasing bottom offset moves opening upward")
	var fixed := _settings()
	previous = _boundary.opening_edge(0)
	_boundary.height += 60.0
	await _sync_layout()
	_check_unchanged(fixed, ["height"])
	_check(_boundary.opening_edge(0).is_equal_approx(previous + Vector2(0.0, 60.0)),
		"Opening follows lower reference while retaining its offset")
	_check(_boundary.global_position == origin, "Height does not move the upper wall")
	_fixture()
	await _sync_layout()


func _test_setting_independence() -> void:
	var fixed := _settings()
	var origin := _boundary.global_position
	var old_start := _boundary.sample_interval(0.0, 0)
	var old_length := _boundary.left_flipper_length
	var old_connection := _boundary.connection_position(0)
	_check(not _lower_hit(168.0).is_empty(), "Original opening has collision outside its edge")
	_boundary.opening_width = 384.0
	await _sync_layout()
	_check_unchanged(fixed, ["opening_width"])
	_check(_boundary.global_position == origin, "Opening width does not move the upper wall")
	_check(is_equal_approx(_boundary.sample_interval(0.0, 0).x, old_start.x),
		"Opening width does not slide the flipper start along the lower line")
	_check(_boundary.left_flipper_length < old_length, "Opening width changes derived flipper length")
	_check(_lower_hit(168.0).is_empty(), "Widened opening removes collision inside the new gap")
	_check(not _boundary.connection_position(0).is_equal_approx(old_connection),
		"Outer connection follows the fixed opening and angle")
	_check_lower_angles()

	fixed = _settings()
	old_start = _boundary.sample_interval(0.0, 0)
	old_connection = _boundary.connection_position(0)
	_boundary.opening_offset.y += 60.0
	await _sync_layout()
	_check_unchanged(fixed, ["opening_offset"])
	_check(_boundary.global_position == origin, "Opening height does not move the upper wall")
	_check(_boundary.connection_position(0).is_equal_approx(old_connection - Vector2(0.0, 60.0)),
		"Opening height translates the outer connection")
	_check(_boundary.sample_interval(0.0, 0).is_equal_approx(old_start - Vector2(0.0, 60.0)),
		"Opening height translates the flipper without changing its start distance")

	fixed = _settings()
	var edges := [_boundary.opening_edge(0), _boundary.opening_edge(1)]
	_boundary.lower_angle = 28.0
	await _sync_layout()
	_check_unchanged(fixed, ["lower_angle"])
	for side: int in 2:
		_check(_boundary.opening_edge(side) == edges[side], "Angle keeps opening edge fixed")
		_check(is_equal_approx(_boundary.connection_position(side).distance_to(
			_boundary.sample_interval(0.0, side)), _boundary.start_distance),
			"Angle preserves the outer start distance")
	_check_lower_angles()

	fixed = _settings()
	_boundary.opening_offset.x = 36.0
	await _sync_layout()
	_check_unchanged(fixed, ["opening_offset"])
	_check(_boundary.left_lower_length > _boundary.right_lower_length,
		"Horizontal opening offset produces independent derived side lengths")
	_check_lower_angles()

	fixed = _settings()
	old_start = _boundary.sample_interval(0.0, 0)
	old_length = _boundary.left_flipper_length
	_boundary.opening_margin = 24.0
	await _sync_layout()
	_check_unchanged(fixed, ["opening_margin"])
	_check(_boundary.sample_interval(0.0, 0).is_equal_approx(old_start), "Opening margin keeps start fixed")
	_check(is_equal_approx(_boundary.left_flipper_length, old_length - 24.0), "Opening margin shortens interval")
	_check(is_equal_approx(_boundary.sample_interval(1.0, 0).distance_to(
		_boundary.opening_edge(0)), 24.0), "Opening margin is measured along the straight line")

	_boundary.start_distance = 0.0
	await _sync_layout()
	_check(is_zero_approx(_boundary.start_distance), "Invalid start is not silently moved")
	_check(is_zero_approx(_boundary.left_flipper_length), "A start inside the rounded corner disables the interval")
	_check(not _boundary._get_configuration_warnings().is_empty(), "Invalid interval reports a warning")
	_boundary.start_distance = 330.0
	_boundary.opening_margin = 1200.0
	await _sync_layout()
	_check(is_equal_approx(_boundary.opening_margin, 1200.0), "Oversized margin is not silently clamped")
	_check(not _main.flippers.items[0].visible, "Invalid interval cannot predict a shot")

	_fixture()
	fixed = _settings()
	_boundary.opening_width = _boundary.width + 48.0
	await _sync_layout()
	_check_unchanged(fixed, ["opening_width"])
	_check(not _boundary._get_configuration_warnings().is_empty(), "Invalid opening reports a warning")
	_check(is_zero_approx(_boundary.left_flipper_length), "Invalid opening disables the flipper")

	_fixture()
	_boundary.opening_offset.y = _boundary.height - 240.0
	await _sync_layout()
	_check(_boundary.upper_corner_radius > _boundary.upper_radius_limit, "Tight geometry exposes corner radius limit")
	_check(not _boundary._get_configuration_warnings().is_empty(), "Limited corner radius reports a warning")
	_check(is_equal_approx(_boundary.upper_corner_radius, 72.0), "Radius setting is preserved")
	_fixture()
	await _sync_layout()


func _test_slider_updates() -> void:
	var notifications: Array[int] = [0]
	var on_property_list_changed := func() -> void:
		notifications[0] += 1
	_boundary.property_list_changed.connect(on_property_list_changed)
	var old_length := _boundary.left_lower_length
	for index in 30:
		_boundary.opening_width = 288.0 + index * 6.0
		_boundary.lower_angle = 10.0 + index * 0.25
		await process_frame
		await process_frame
		_check(_boundary.left_flipper_length > 0.0, "Computed values update during continuous edits")
	_check(notifications[0] == 0, "Continuous edits do not rebuild Inspector property controls")
	_check(not is_equal_approx(_boundary.left_lower_length, old_length), "Read-only geometry follows slider edits")
	_boundary.property_list_changed.disconnect(on_property_list_changed)
	_fixture()
	await _sync_layout()


func _setting_names() -> Array[String]:
	return ["width", "height", "opening_width", "opening_offset", "lower_angle", "upper_corner_radius",
		"lower_corner_radius", "start_distance", "opening_margin",
		"wall_restitution", "lower_restitution"]


func _settings() -> Dictionary:
	var settings := {}
	for name: String in _setting_names():
		settings[name] = _boundary.get(name)
	return settings


func _check_unchanged(before: Dictionary, changed: Array[String]) -> void:
	for name: String in _setting_names():
		if name not in changed:
			_check(_boundary.get(name) == before[name], name + " stays unchanged")


func _check_lower_angles() -> void:
	for side: int in 2:
		var direction := _boundary.opening_edge(side) - _boundary.connection_position(side)
		var angle := rad_to_deg(atan2(direction.y, absf(direction.x)))
		_check(absf(angle - _boundary.lower_angle) < 0.001, "Each lower side retains the specified angle")
		var middle := (_boundary.opening_edge(side) + _boundary.connection_position(side)) * 0.5
		var hit := _lower_hit(middle.x)
		_check(not hit.is_empty(), "Updated lower line has collision")
		if not hit.is_empty():
			var contact: Vector2 = hit["position"]
			_check(_boundary.to_local(contact).distance_to(middle) < 0.1, "Collision follows updated geometry")


func _lower_hit(x: float) -> Dictionary:
	var query := PhysicsRayQueryParameters2D.create(
		_boundary.to_global(Vector2(x, _boundary.opening_center.y - 360.0)),
		_boundary.to_global(Vector2(x, _boundary.opening_center.y + 120.0)), 2)
	return _ball.get_world_2d().direct_space_state.intersect_ray(query)


func _fixture() -> void:
	_boundary.width = 1392.0
	_boundary.height = 1080.0
	_boundary.opening_width = 288.0
	_boundary.opening_offset = Vector2(0.0, 162.0)
	_boundary.lower_angle = 18.6
	_boundary.upper_corner_radius = 72.0
	_boundary.lower_corner_radius = 72.0
	_boundary.start_distance = 330.0
	_boundary.opening_margin = 0.0
	_main.flippers.root_angle = -20.0
	_main.flippers.tip_angle = 40.0
	_main.flippers.power_equalization = 0.0


func _sync_layout() -> void:
	await process_frame
	await process_frame
	await physics_frame
	await physics_frame


func _test_sides_and_top() -> void:
	_ball.gravity = 0.0
	var original_restitution := _boundary.wall_restitution
	for bounce: float in [0.0, 0.25, 1.0]:
		_boundary.wall_restitution = bounce
		for rate: float in [30.0, 60.0, 120.0]:
			for side: float in [-1.0, 1.0]:
				var wall := _boundary.to_global(Vector2(side * _boundary.width * 0.5, 360.0))
				_main.place_ball(wall - Vector2(side * (_ball.radius + 6.0), 0.0), Vector2(side * 1950.0, 0.0))
				_ball.advance(1.0 / rate)
				_check(absf(_ball.velocity.x + side * 1950.0 * bounce) < 0.1,
					"Wall restitution %.2f controls side reflection at %d Hz" % [bounce, rate])
			var top := _boundary.to_global(Vector2.ZERO)
			_main.place_ball(top + Vector2.DOWN * (_ball.radius + 6.0), Vector2.UP * 1950.0)
			_ball.advance(1.0 / rate)
			_check(absf(_ball.velocity.y - 1950.0 * bounce) < 0.1,
				"Wall restitution %.2f controls ceiling reflection at %d Hz" % [bounce, rate])
			_check(_ball.position.y >= top.y + _ball.radius - 0.1, "Ceiling contains the ball")
	_boundary.wall_restitution = original_restitution
	_ball.gravity = 2100.0

func _test_rounded_corners() -> void:
	var corners := PackedVector2Array([
		Vector2(-_boundary.width * 0.5, 0.0), Vector2(_boundary.width * 0.5, 0.0),
		_boundary.connection_position(0), _boundary.connection_position(1),
	])
	var inward := PackedVector2Array([
		Vector2(1.0, 1.0), Vector2(-1.0, 1.0),
		Vector2(1.0, -1.0), Vector2(-1.0, -1.0),
	])
	_ball.gravity = 0.0
	_main.flippers.reset_input()
	for index in corners.size():
		var direction := inward[index].normalized()
		var point := _boundary.to_global(corners[index])
		var query := PhysicsRayQueryParameters2D.create(
			point + direction * 120.0, point - direction * 15.0, 2)
		var hit := _ball.get_world_2d().direct_space_state.intersect_ray(query)
		_check(not hit.is_empty(), "Rounded corner has collision")
		if hit.is_empty():
			continue
		var contact: Vector2 = hit["position"]
		var normal: Vector2 = hit["normal"]
		_check(contact.distance_to(point) > 1.0, "Corner no longer reaches the sharp vertex")
		_check(absf(normal.x) > 0.1 and absf(normal.y) > 0.1, "Corner has an intermediate surface normal")
		_main.place_ball(contact + normal * (_ball.radius + 6.0), -normal * 600.0)
		for _step in 12:
			_ball.advance(TEST_STEP)
		_check(_ball.velocity.dot(normal) > 1.0, "Ball reflects from the rounded corner")
	_ball.gravity = 2100.0


func _test_lower_contacts() -> void:
	_ball.gravity = 0.0
	_main.flippers.reset_input()
	var length := _boundary.lower_length(0)
	for side: int in 2:
		for distance: float in [90.0, 180.0, 327.0, 333.0, length - 12.0]:
			var start := _boundary.connection_position(side)
			var tangent := (_boundary.opening_edge(side) - start).normalized()
			var local_point := start + tangent * distance
			var normal := Vector2(tangent.y, -tangent.x) * (1.0 if side == 0 else -1.0)
			var point := _boundary.to_global(local_point)
			_main.place_ball(point + normal * (_ball.radius + 6.0), -normal * 1950.0)
			for _step in 6:
				_ball.advance(TEST_STEP)
			_check(_ball.velocity.dot(normal) > 0.0, "Lower edge reflects at distance %.1f" % distance)
	for side: int in 2:
		for ratio: float in [0.02, 0.25, 0.5, 0.75, 0.98]:
			var contact := _contact_at(ratio, side)
			var point := _boundary.to_global(contact[0])
			var normal: Vector2 = contact[1]
			_main.place_ball(point + normal * (_ball.radius + 24.0), -normal * 1500.0)
			for _step in 24:
				_ball.advance(TEST_STEP)
			_check(_ball.velocity.dot(normal) > 0.0, "Straight lower edge reflects on side %d at %.2f" % [side, ratio])
			_check(is_equal_approx(_boundary.rotation, 0.0), "Surface does not rotate")
	var original_restitution := _boundary.lower_restitution
	for side: int in 2:
		var contact := _contact_at(0.5, side)
		var point := _boundary.to_global(contact[0])
		var normal: Vector2 = contact[1]
		for bounce: float in [0.0, 0.25, 1.0]:
			_boundary.lower_restitution = bounce
			_main.flippers.restitution = bounce
			_main.place_ball(point + normal * (_ball.radius + 6.0), -normal * 600.0)
			for _step in 12:
				_ball.advance(TEST_STEP)
			_check(absf(_ball.velocity.dot(normal) - 600.0 * bounce) < 0.1,
				"Lower restitution controls the unpressed flipper interval")
	_boundary.lower_restitution = 0.0
	_main.flippers.restitution = 0.0
	_ball.gravity = 2100.0
	for side: int in 2:
		var contact := _contact_at(0.1, side)
		var point := _boundary.to_global(contact[0])
		var normal: Vector2 = contact[1]
		_main.place_ball(point + normal * (_ball.radius + 6.0))
		var maximum_outward := 0.0
		for _step in 30:
			_ball.advance(TEST_STEP)
			maximum_outward = maxf(maximum_outward, _ball.velocity.dot(normal))
		# This is the previous 1-unit/s tolerance converted to the 1920-wide coordinate scale.
		_check(maximum_outward < 3.0, "Zero restitution does not bounce under gravity: %.5f" % maximum_outward)
	_boundary.lower_restitution = original_restitution
	_main.flippers.restitution = original_restitution


func _test_connections() -> void:
	_ball.gravity = 0.0
	_main.flippers.reset_input()
	for angle: float in [0.0, 10.5, 28.0, 45.0]:
		_boundary.lower_angle = angle
		_boundary.opening_margin = 36.0
		await _sync_layout()
		for side: int in 2:
			var start := _boundary.to_global(_boundary.sample_interval(0.0, side))
			var end := _boundary.to_global(_boundary.sample_interval(1.0, side))
			var tangent := (end - start).normalized()
			var normal := Vector2(tangent.y, -tangent.x) * (1.0 if side == 0 else -1.0)
			for joint: Vector2 in [start, end]:
				for distance: float in [-12.0, -0.5, 0.5, 12.0]:
					var point := joint + tangent * distance
					var hit := _ray(point + normal * 45.0, point - normal * 45.0)
					_check(not hit.is_empty(), "Connection has no collision gap")
					if not hit.is_empty():
						var actual: Vector2 = hit["position"]
						_check(actual.distance_to(point) < 0.01,
							"Wall and flipper surfaces are flush on both sides of the joint")
			for direction: float in [-1.0, 1.0]:
				var velocity := tangent * direction * 450.0
				_main.place_ball(start - tangent * direction * 60.0
					+ normal * (_ball.radius + 0.06), velocity)
				for _step in 64:
					_ball.advance(TEST_STEP)
				_check(_ball.velocity.distance_to(velocity) < 0.1,
					"Ball crosses the pivot in either direction without catching or bouncing")
	_fixture()
	await _sync_layout()
	_ball.gravity = 2100.0


func _test_strikes() -> void:
	_ball.gravity = 0.0
	var maximum := _ball.max_speed
	_ball.max_speed = 3600.0
	for side: int in 2:
		var flipper := _main.flippers.items[side]
		_main.flippers.reset_input()
		var pivot := flipper.global_position
		var rest_tip := flipper.tip_position()
		_main.flippers.advance(0.5, side == 0, side == 1)
		var raised_tip := flipper.tip_position()
		_check(flipper.global_position.is_equal_approx(pivot), "Outer endpoint is the fixed pivot")
		_check(raised_tip.y < rest_tip.y - 0.1, "Only the active interval rotates upward")
		_check(absf(absf((rest_tip - pivot).angle_to(raised_tip - pivot))
			- deg_to_rad(_main.flippers.swing_angle)) < 0.001, "Swing angle controls the raised pose")
		_main.flippers.advance(0.5, side == 0, side == 1)
		_check(flipper.tip_position().is_equal_approx(raised_tip), "Holding keeps raised pose")
		_check(is_zero_approx(flipper.angular_velocity), "Held flipper has no surface velocity")
		_check(not flipper.is_rising(), "Held flipper does not redirect the ball")
		await _sync_layout()
		# The old resting interval must become an actual gap when the flipper rises.
		var old_middle := _boundary.to_global(_boundary.sample_interval(0.5, side))
		var hit := _ray(old_middle + Vector2.UP * 24.0, old_middle + Vector2.DOWN * 24.0)
		_check(hit.is_empty(), "No invisible resting wall remains below the raised flipper")
		var normal := flipper.strike_normal()
		var middle := flipper.root_surface_position().lerp(raised_tip, 0.5)
		hit = _ray(middle + normal * 45.0, middle - normal * 45.0)
		_check(not hit.is_empty() and hit["collider"] == flipper, "Collision follows raised pose")
		for bounce: float in [0.0, 0.25, 1.0]:
			_boundary.lower_restitution = bounce
			_main.flippers.restitution = bounce
			_boundary.wall_restitution = 1.0 - bounce
			_main.place_ball(middle + normal * (_ball.radius + 6.0), -normal * 600.0)
			for _step in 12:
				_ball.advance(TEST_STEP)
			_check(absf(_ball.velocity.dot(normal) - 600.0 * bounce) < 0.2,
				"Held flipper uses its own restitution independently of walls")
		_boundary.lower_restitution = 0.1
		_main.flippers.restitution = 0.1
		_boundary.wall_restitution = 0.1
		_main.flippers.advance(0.01, false, false)
		_check(flipper.tip_position().y > raised_tip.y, "Release starts returning")
		_check(absf(flipper.angular_velocity) > 0.0, "Return motion has surface velocity")
		_check(not flipper.is_rising(), "Returning flipper does not redirect the ball")
		_test_return_contact(flipper)
		_main.flippers.advance(1.0, false, false)
		_check(flipper.tip_position().is_equal_approx(rest_tip), "Release returns to the original line")

	# Observe actual hits at different lever arms and configured motor speeds.
	for side: int in 2:
		var slow_near := _moving_hit(side, 0.2, 360.0, 0.0, 60.0)
		var slow_far := _moving_hit(side, 0.8, 360.0, 0.0, 60.0)
		var fast_far := _moving_hit(side, 0.8, 720.0, 0.0, 60.0)
		_check(slow_far.length() > slow_near.length() + 300.0, "Tip speed increases with distance from pivot")
		_check(fast_far.length() > slow_far.length() + 300.0, "Rotation speed affects ball speed")
		var incoming := _moving_hit(side, 0.5, 360.0, 600.0, 60.0)
		var stationary := _moving_hit(side, 0.5, 360.0, 0.0, 60.0)
		_check(incoming.length() > stationary.length() + 30.0, "Incoming ball speed contributes to rebound")
		for rate: float in [30.0, 60.0, 120.0]:
			var result := _moving_hit(side, 0.8, 1440.0, 0.0, rate)
			_check(result.y < -300.0, "Fast flipper does not pass through a stationary ball at %d Hz" % rate)
	# Both endpoint angles remain editable without rebuilding the geometry.
	_main.flippers.root_angle = -35.0
	_main.flippers.tip_angle = 25.0
	for side: int in 2:
		for ratio: float in [0.05, 0.5, 0.95]:
			_moving_hit(side, ratio, 540.0, 300.0, 60.0)
	_main.flippers.root_angle = -20.0
	_main.flippers.tip_angle = 40.0
	_main.flippers.raise_speed = 720.0
	_main.flippers.reset_input()
	_ball.max_speed = maximum
	_ball.gravity = 2100.0
	await _sync_layout()
	_test_space_hold()


func _test_power_equalization() -> void:
	_ball.gravity = 0.0
	var maximum := _ball.max_speed
	_ball.max_speed = 3600.0
	for side: int in 2:
		var previous_gap := INF
		var previous_near := 0.0
		var flipper := _main.flippers.items[side]
		for amount: float in [0.0, 0.5, 1.0]:
			_main.flippers.power_equalization = amount
			var near := _moving_hit(side, 0.15, 360.0, 0.0, 60.0)
			var far := _moving_hit(side, 0.85, 360.0, 0.0, 60.0)
			var gap := absf(far.length() - near.length())
			_check(near.length() > previous_near, "Increasing equalization raises root-side power")
			_check(gap < previous_gap, "Increasing equalization reduces the position-dependent speed gap")
			previous_near = near.length()
			previous_gap = gap
			if amount == 1.0:
				_check(gap < 1.0, "Full equalization gives near and far hits the same rotation contribution")
			for rate: float in [30.0, 120.0]:
				_moving_hit(side, 0.25, 360.0, 450.0, rate)
			var tip := flipper.tip_position()
			_check(flipper.surface_velocity_at(tip, amount).is_equal_approx(
				flipper.surface_velocity_at(tip)), "Tip power is unchanged by equalization")
		var stationary := _moving_hit(side, 0.5, 360.0, 0.0, 60.0)
		var incoming := _moving_hit(side, 0.5, 360.0, 600.0, 60.0)
		_check(incoming.length() > stationary.length() + 30.0, "Equalization preserves incoming speed influence")
		var bounce := _boundary.lower_restitution
		_boundary.lower_restitution = 0.8
		_main.flippers.restitution = 0.8
		var elastic := _moving_hit(side, 0.5, 360.0, 0.0, 60.0)
		_check(elastic.length() > stationary.length() + 300.0, "Equalization preserves restitution influence")
		_boundary.lower_restitution = bounce
		_main.flippers.restitution = bounce
		_main.flippers.reset_input()
		_main.flippers.advance(0.5, side == 0, side == 1)
		_main.flippers.advance(0.1, side == 0, side == 1)
		_test_return_contact(flipper)
		_main.flippers.advance(0.01, false, false)
		_test_return_contact(flipper)
	_main.flippers.reset_input()
	_main.flippers.power_equalization = 0.5
	_main.flippers.raise_speed = 720.0
	_ball.max_speed = maximum
	_ball.gravity = 2100.0
	await _sync_layout()


func _moving_hit(side: int, ratio: float, speed: float, incoming: float, rate: float) -> Vector2:
	_main.flippers.raise_speed = speed
	_main.flippers.reset_input()
	var contact := _contact_at(ratio, side)
	var point := _boundary.to_global(contact[0])
	var normal := contact[1]
	_main.place_ball(point + normal * (_ball.radius + 6.0),
		-normal * incoming)
	var flipper := _main.flippers.items[side]
	var initial_velocity := _ball.velocity
	var first_contact := {}
	var on_bounced := func(hit_point: Vector2, hit_normal: Vector2) -> void:
		if not first_contact.is_empty():
			return
		first_contact["actual"] = _ball.velocity
		var effective_arm := (hit_point - flipper.global_position).lerp(
			flipper.tip_position() - flipper.global_position, _main.flippers.power_equalization)
		var rotating := Vector2(-effective_arm.y, effective_arm.x) * flipper.angular_velocity
		var upper_normal := flipper.strike_normal()
		var surface := Vector2(0, rotating.dot(upper_normal) / upper_normal.y)
		first_contact["physical"] = PinballBall.reflected_velocity(initial_velocity, hit_normal,
			_main.flippers.restitution, surface)
		var arm := flipper.tip_position() - flipper.root_surface_position()
		first_contact["ratio"] = clampf((hit_point - flipper.root_surface_position()).dot(arm)
			/ arm.length_squared(), 0.0, 1.0)
		first_contact["rising"] = flipper.is_rising()
	_ball.bounced.connect(on_bounced)
	var predicted := _main.predict_shot()
	_check(predicted.length() > 0.0, "Moving flipper hit has a direction preview")
	_check(is_zero_approx(_main.flippers.items[side].angular_velocity), "Prediction does not move the flipper")
	var detected := false
	var result := Vector2.ZERO
	for _frame in 3:
		var remaining := 1.0 / rate
		while remaining > 0.000001:
			var step := minf(minf(TEST_STEP, remaining),
				_main.flippers.motion_step_limit(_ball.radius, side == 0, side == 1))
			_main.flippers.advance(step, side == 0, side == 1)
			_ball.advance(step)
			if not detected and _ball.last_normal != Vector2.ZERO:
				detected = true
				result = _ball.velocity
			remaining -= step
	_ball.bounced.disconnect(on_bounced)
	_check(detected, "Rotating flipper actually contacts the ball")
	if not first_contact.is_empty():
		var actual: Vector2 = first_contact["actual"]
		var physical: Vector2 = first_contact["physical"]
		var angle := lerpf(_main.flippers.root_angle, _main.flippers.tip_angle, first_contact["ratio"])
		var expected := Vector2.UP.rotated(deg_to_rad(angle * (1.0 if side == 0 else -1.0)))
		_check(first_contact["rising"], "Contact occurs while the flipper rises")
		_check(absf(actual.angle_to(expected)) < deg_to_rad(0.01),
			"Actual shot direction follows contact position in world coordinates")
		_check(absf(actual.length() - physical.length()) < 0.01,
			"Direction correction preserves the physically calculated speed: actual %.3f expected %.3f side %d ratio %.2f" % [actual.length(), physical.length(), side, ratio])
	if detected:
		_check(absf(predicted.angle_to(result)) < deg_to_rad(4.0),
			"Direction preview matches rotating collision: %.2f degrees" % rad_to_deg(predicted.angle_to(result)))
	return first_contact.get("actual", result).limit_length(_ball.max_speed)


func _test_return_contact(flipper: PinballFlipper) -> void:
	var arm := flipper.tip_position() - flipper.root_surface_position()
	var tangent := arm.normalized()
	var normal := Vector2(tangent.y, -tangent.x) * (1.0 if flipper.side == 0 else -1.0)
	var point := flipper.root_surface_position() + arm * 0.5
	_main.place_ball(point + normal * (_ball.radius + 1.0), -normal * 2700.0 + tangent * 225.0)
	var incoming := _ball.velocity
	var responses: Array[Vector2] = []
	var on_bounced := func(hit_point: Vector2, hit_normal: Vector2) -> void:
		if responses.is_empty():
			responses.append(_ball.velocity)
			responses.append(PinballBall.reflected_velocity(incoming, hit_normal,
				_main.flippers.restitution, flipper.surface_velocity_at(hit_point)))
	_ball.bounced.connect(on_bounced)
	_ball.advance(TEST_STEP)
	_ball.bounced.disconnect(on_bounced)
	_check(responses.size() == 2, "Ball contacts the returning flipper")
	if responses.size() == 2:
		_check(responses[0].distance_to(responses[1]) < 0.01,
			"Return motion uses physical reflection without position-based redirection")


func _test_space_hold() -> void:
	_main.flippers.reset_input()
	var event := InputEventKey.new()
	event.keycode = KEY_SPACE
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	_check(Input.is_action_pressed(&"pinball_left") and Input.is_action_pressed(&"pinball_right"),
		"Space holds both flippers")
	_main.advance(0.2)
	var left := _main.flippers.items[0].tip_position()
	var right := _main.flippers.items[1].tip_position()
	_main.advance(0.3)
	_check(left.is_equal_approx(_main.flippers.items[0].tip_position())
		and right.is_equal_approx(_main.flippers.items[1].tip_position()), "Space keeps both raised")
	var release := event.duplicate() as InputEventKey
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	_main.advance(0.3)
	for side: int in 2:
		_check(_main.flippers.items[side].tip_position().distance_to(
			_boundary.to_global(_boundary.sample_interval(1.0, side))) < 0.01,
			"Releasing Space lowers both flippers")


func _ray(start: Vector2, end: Vector2) -> Dictionary:
	return _ball.get_world_2d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters2D.create(start, end, 2))


func _test_bumper_missiles(bumper: PinballBumper) -> void:
	var launcher := _main.launcher
	_check(launcher.missile_scene == preload("res://missiles/homing_1.tscn"),
		"The playfield launcher uses Homing 1")
	launcher.volley_size = 2
	var point := bumper.global_position + Vector2(0.0, -bumper.radius)
	bumper.hit(point)
	launcher.advance(0.0, _main.enemies)
	var missiles := launcher.get_children()
	_check(missiles.size() == 2, "A bumper hit fires the configured volley in one step")
	for child: Node in missiles:
		var missile := child as Projectile
		_check(missile != null and missile.global_position.is_equal_approx(bumper.global_position)
			and missile.penetration_limit == 5
			and missile._remaining_penetrations == missile.penetration_limit,
			"Each missile starts at the bumper center with the configured penetration limit")
	launcher.free()
	bumper.hit(point)
	_main.advance(TEST_STEP)
	_check(not is_instance_valid(_main.launcher), "The playfield advances without a launcher")


func _test_bumper_and_respawn() -> void:
	var bumper := preload("res://pinball/bumper.tscn").instantiate() as PinballBumper
	bumper.position = Vector2(1800.0, 240.0)
	bumper.hit_sound = null
	root.add_child(bumper)
	_ball.gravity = 0.0
	_main.place_ball(bumper.global_position + Vector2(0.0, -105.0), Vector2(0.0, 300.0))
	for _step in 40:
		_ball.advance(TEST_STEP)
	_check(_ball.velocity.y < -1350.0, "Bumper preserves minimum exit speed")
	bumper.queue_free()
	_ball.gravity = 2100.0
	_main.place_ball(_boundary.to_global(_boundary.opening_center) + Vector2(0.0, 84.0), Vector2(0.0, 600.0))
	_main.advance(0.1)
	_check(not _ball.active, "Ball drains through the open gap")
	_main.advance(_main.respawn_delay + 0.05)
	_check(_ball.active, "Ball respawns")
	_check(_ball.position.distance_to(Vector2(780.0, 540.0)) < 15.0, "Initial scene placement is the spawn")


func _test_layout() -> void:
	for rate: float in [30.0, 60.0, 120.0]:
		_main.reset_ball()
		var contacts := 0
		for frame in int(rate * 10.0):
			if frame % int(rate * 0.4) == 0:
				Input.action_press(&"pinball_left")
				Input.action_press(&"pinball_right")
			elif frame % int(rate * 0.4) == 2:
				Input.action_release(&"pinball_left")
				Input.action_release(&"pinball_right")
			var previous := _ball.last_contact
			_main.advance(1.0 / rate)
			if _ball.last_contact != previous:
				contacts += 1
			if _ball.active:
				_check(_ball.velocity.length() <= _ball.max_speed + 0.1, "Speed cap")
				_check(absf(_boundary.to_local(_ball.global_position).x) < _boundary.width * 0.5 + 0.1,
					"Ball stays between side boundaries")
		Input.action_release(&"pinball_left")
		Input.action_release(&"pinball_right")
		_check(contacts >= 3, "Layout produces repeated contacts at %d Hz" % rate)
		print("Layout %d Hz contacts: %d" % [rate, contacts])


func _contact_at(ratio: float, side: int) -> Array[Vector2]:
	var point := _boundary.sample_interval(ratio, side)
	var previous := _boundary.sample_interval(maxf(0.0, ratio - 0.001), side)
	var next := _boundary.sample_interval(minf(1.0, ratio + 0.001), side)
	var tangent := (next - previous).normalized()
	var normal := Vector2(tangent.y, -tangent.x)
	if side == 1:
		normal = -normal
	return [point, normal]


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
