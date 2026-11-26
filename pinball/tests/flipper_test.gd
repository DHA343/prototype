extends SceneTree

const MAIN: PackedScene = preload("res://main/main.tscn")
const STEP: float = 1.0 / 240.0

var _main: PinballLab
var _flippers: PinballFlippers
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = MAIN.instantiate() as PinballLab
	(_main.get_node("EnemySpawner") as EnemySpawner).enabled = false
	root.add_child(_main)
	_main.set_physics_process(false)
	_main.get_node("Playfield/ShotGuide").set_physics_process(false)
	_flippers = _main.flippers
	await physics_frame
	await physics_frame

	_test_whole_update()
	_test_faces()
	_test_recorded_contacts()
	_test_interval_start()
	await _test_native_then_sweep()
	await _test_shared_motion()
	_test_prediction()
	await _test_prediction_blockers()

	for failure: String in _failures:
		printerr("FAIL: " + failure)
	print("Flipper checks: %d; failures: %d" % [_checks, _failures.size()])
	_main.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _test_whole_update() -> void:
	var ball := _main.ball
	ball.radius = 6.0
	_flippers.raise_speed = 1440.0
	_main.place_ball(Vector2(960, 650))
	Input.action_press(&"pinball_left")
	for delta: float in [1.0 / 60.0, 1.0 / 30.0]:
		var start := ball.global_position
		var outgoing := ball.velocity + Vector2.DOWN * ball.gravity * delta
		_main.advance(delta)
		_check(ball.velocity.is_equal_approx(outgoing)
			and ball.global_position.is_equal_approx(start + outgoing * delta),
			"Main must integrate one whole update at the caller's delta")
	Input.action_release(&"pinball_left")
	_flippers.raise_speed = 600.0
	ball.radius = 24.0
	_main.reset_ball()


func _test_faces() -> void:
	_flippers.advance(0.01, true, true)
	for item: PinballFlipper in _flippers.items:
		var table := item as TableFlipper
		var pose := table.global_transform
		var outline := table._outline.duplicate()
		var applied: PackedVector2Array = table.get_node("CollisionShape2D").shape.points
		var points := table.world_polygon_at(pose)
		var upward := (points[1] - points[0]).orthogonal().normalized()
		for index: int in 4:
			var a := points[index]
			var b := points[(index + 1) % 4]
			var midpoint := a.lerp(b, 0.5)
			var normal := (b - a).orthogonal().normalized()
			var overlap := table._contact_at(midpoint - normal * 2.0, 6.0, pose, 0.0, 0.0)
			_check(not overlap.is_empty() and overlap.depth > 6.0,
				"Contact outline includes the interior")
			var is_top := index == 0
			_check(table._contact_at(midpoint + normal * 7.0, 6.0, pose, 0.0, 0.0).is_empty(),
				"Contact outline rejects a point outside the circle's reach")
			_for_face(table, midpoint + normal * 5.5, is_top)
		for index: int in 2:
			var outward := Vector2.LEFT if index == 0 else Vector2.RIGHT
			var normal := (outward + upward * 0.15).normalized()
			var corner := _for_face(table, points[index] + normal * 5.5, true)
			_check(not corner.is_empty() and (corner.normal as Vector2).dot(upward) < 0.5,
				"Endpoint fixture exercises the old contact-angle limit")
		var center := points[0].lerp(points[1], 0.5) + upward * 5.5
		for omega: float in [0.0, -table.angular_velocity]:
			var hit := table._contact_at(center, 6.0, pose, omega, 0.5)
			_check(hit.on_shot_face and not hit.is_striking,
				"Held and returning tops only reflect normally")
			_check(hit.strike_surface_velocity == hit.surface_velocity,
				"Held and returning tops use physical surface speed")
		var other_pose := _flippers.plan_motion(true, true)[table.side].pose_at(0.002)
		table._contact_at(center, 6.0, other_pose, table.angular_velocity, 0.5)
		_check(table._outline == outline and table.polygon_at(pose) == applied
			and table.get_node("CollisionShape2D").shape.points == applied,
			"Contact queries do not mutate drawing or the active collision resource")
	_main.reset_ball()


func _for_face(table: TableFlipper, center: Vector2, top: bool) -> Dictionary:
	var hit := table._contact_at(center, 6.0, table.global_transform, table.angular_velocity, 0.5)
	_check(not hit.is_empty(), "Face fixture has a contact")
	if hit.is_empty():
		return hit
	var native := table.contact_info(hit.point, hit.normal, 0.5)
	_check(hit.on_shot_face == top and hit.is_striking == top and native.is_striking == top,
		"Native and swept contact agree on the upper edge and endpoints")
	_check((native.surface_velocity as Vector2).is_equal_approx(hit.surface_velocity)
		and (native.strike_surface_velocity as Vector2).is_equal_approx(hit.strike_surface_velocity),
		"Native and swept contact use the same physical and powered surface velocities")
	var normal: Vector2 = hit.normal
	var surface: Vector2 = hit.surface_velocity
	_check(PinballMotion.is_flip_shot(hit, PinballMotion.flipper_approach_speed(surface - normal, hit)) == top,
		"Approach is relative to the physical surface")
	_check(not PinballMotion.is_flip_shot(hit, PinballMotion.flipper_approach_speed(surface + normal, hit)),
		"A separating ball cannot trigger a shot")
	return hit


func _test_recorded_contacts() -> void:
	var motion := _make_mover(6.0)
	motion.body.collision_mask = 0
	# separation_response.json, moving_edges 96: shallow tip normal used to reject the shot.
	_place_mover(motion, 6.0, Vector2(922.766846, 1046.035522), Vector2(-230.652542, 191.831711))
	_advance_mover(motion, 1.0 / 30.0, true, false)
	_check_first(motion, Vector2(918.000061, 1047.448242), Vector2(0.965009, -0.262216),
		Vector2(542.748901, -648.293152), Vector2(1.377677, -0.374348))
	_check(_flippers.is_target_disabled(motion.body.get_instance_id()), "Endpoint shot starts guard 3")

	# Force an inward direction for the same contact and preserve the powered physical response.
	_main.reset_ball()
	_flippers.root_angle = -70.0
	_flippers.tip_angle = -70.0
	_place_mover(motion, 6.0, Vector2(922.766846, 1046.035522), Vector2(-230.652542, 191.831711))
	_advance_mover(motion, 1.0 / 30.0, true, false)
	var hit := _first(motion)
	if not hit.is_empty():
		_check(hit.is_striking and _flippers.outward_shot_direction(hit) == Vector2.ZERO,
			"Inward shot direction falls back to physical reflection")
		var physical := PinballMotion.reflected_velocity(
			hit.incoming, hit.normal, _flippers.restitution, hit.strike_surface_velocity)
		_check((hit.outgoing as Vector2).is_equal_approx(physical)
			and _flippers.is_target_disabled(motion.body.get_instance_id()),
			"Fallback preserves powered reflection and guard 3")
	_flippers.root_angle = -20.0
	_flippers.tip_angle = 40.0

	# separation_response.json, moving_edges 1885: returning right underside.
	_main.reset_ball()
	_flippers.advance(0.03, true, true)
	_place_mover(motion, 36.0, Vector2(1131.757080, 1152.048462), Vector2(0, -3600))
	_advance_mover(motion, 1.0 / 30.0, false, false)
	_check_first(motion, Vector2(1131.757080, 1115.848511), Vector2.DOWN,
		Vector2(0, 360), Vector2(0, 2.172217))
	_check(not _flippers.is_target_disabled(motion.body.get_instance_id()),
		"Underside reflection does not start guard 3")

	# separation_response.json, moving_edges 1107: same returning plate recontacts in one update.
	_main.reset_ball()
	_flippers.advance(0.03, true, true)
	_place_mover(motion, 6.0, Vector2(929.868225, 953.314514), Vector2(-2373.645020, 2706.623535))
	_advance_mover(motion, 1.0 / 30.0, false, false)
	_check(motion.swept_hits.size() == 6, "Returning plate rechecks the remaining path")
	for contact: Dictionary in motion.swept_hits:
		_check(contact.get("normal_separation", false),
			"A separated recontact in the same update can use normal separation")

	# separation_diagnostics.json, first overlap: retain the upward separation.
	_main.reset_ball()
	_place_mover(motion, 6.0, Vector2(789.299866, 1020.248047), Vector2.ZERO)
	_advance_mover(motion, 1.0 / 60.0, true, true)
	_check_first(motion, Vector2(788.242920, 1025.950928), Vector2(0.182232, -0.983256),
		Vector2(395.956360, -2245.582520), Vector2(0, -0.353711))

	# separation_view.json, B scene 5: an overlap already present on guard release.
	_main.reset_ball()
	_flippers.advance(1.0 / 60.0, true, true)
	_place_mover(motion, 24.0, Vector2(917.509277, 1040.346924), Vector2(1705.959473, 1855.074463))
	motion.gravity = 1500.0
	_flippers.disable_target(motion.body)
	_advance_mover(motion, 1.0 / 60.0, true, true)
	hit = _first(motion)
	if not hit.is_empty():
		_check((hit.correction as Vector2).distance_to(Vector2(0, -60.609653)) < 0.003,
			"Guard release with starting overlap retains the upward correction")
		_check(not hit.guarded and (hit.outgoing as Vector2).is_equal_approx(hit.incoming),
			"Guard releases before the existing overlap is recovered")
	_check(motion.body.get_collision_exceptions().is_empty(), "Temporary sweep and guard exceptions are removed")
	motion.body.free()


func _test_interval_start() -> void:
	_main.reset_ball()
	var motion := _make_mover(6.0)
	var swing := _flippers.plan_motion(true, false)[0]
	var table := swing.flipper as TableFlipper
	var elapsed := 0.015
	var start_polygon := table.world_polygon_at(swing.pose_at(0.0))
	var interval_polygon := table.world_polygon_at(swing.pose_at(elapsed))
	var clear := interval_polygon[0].lerp(interval_polygon[1], 0.5) + Vector2.UP * 28.0
	var initial_overlap := start_polygon[0].lerp(start_polygon[1], 0.5)
	var interval_overlap := interval_polygon[0].lerp(interval_polygon[1], 0.5)
	var hit := {"time": 0.002, "swing": swing}
	motion.body.global_position = interval_overlap
	_check(not motion._is_new_contact(hit, clear, elapsed),
		"Late sweep hit retains old separation if the interval opened in contact")
	motion.body.global_position = clear
	_check(not motion._is_new_contact(hit, initial_overlap, elapsed),
		"Leaving the plate does not erase an overlap at update start")
	_check(motion._is_new_contact(hit, clear, elapsed),
		"Geometry at the sweep clock's two start poses permits a new contact")
	motion.body.global_position = initial_overlap
	_check(not motion._is_new_contact(hit, clear, 0.0),
		"Zero-time recovery can change the next interval's contact state")
	motion.body.free()


func _test_shared_motion() -> void:
	_main.reset_ball()
	var first := _make_mover(24.0)
	var other := _make_mover(24.0)
	var first_id := first.body.get_instance_id()
	var other_id := other.body.get_instance_id()
	await physics_frame
	for strike: int in 2:
		var item := _flippers.items[0] as TableFlipper
		var top := item.world_polygon_at(item.global_transform)
		var position := top[0].lerp(top[1], 0.65) + Vector2.UP * 24.5
		first.body.global_position = position
		first.body.velocity = Vector2.DOWN * 300.0
		other.body.global_position = position if strike == 1 else Vector2(960, 650)
		other.body.velocity = first.body.velocity
		var swings := _flippers.plan_motion(true, false)
		_flippers.advance(STEP, true, false)
		first.advance(STEP, swings)
		other.advance(STEP, swings)
		_check(first.body.velocity.y < 0.0 and _flippers.is_target_disabled(first_id),
			"Shared motion can shoot the same target again during the same upward stroke")
		_check(_flippers.is_target_disabled(other_id) == (strike == 1),
			"Guard 3 is independent for each target")

	_flippers.advance(0.03, true, true)
	_flippers.advance(STEP, true, true)
	var table := _flippers.items[0] as TableFlipper
	var polygon := table.world_polygon_at(table.global_transform)
	var inside := polygon[0].lerp(polygon[2], 0.5)
	first.body.global_position = inside
	first.body.velocity = Vector2.UP * 600.0
	first.advance(STEP)
	_check(first.body.global_position.is_equal_approx(inside + first.body.velocity * STEP),
		"Guarded upward targets pass through a plate without recovery")
	_check(first.body.get_collision_exceptions().is_empty()
		and other.body.get_collision_exceptions().is_empty(), "Guard keeps exceptions local to the update")
	_check(_flippers.items[0].collision_layer == 2 and _flippers.items[1].collision_layer == 2,
		"Per-target guard preserves both collision layers")

	first.gravity = 1500.0
	first.body.velocity = Vector2.UP
	first.advance(STEP)
	_check(not _flippers.is_target_disabled(first_id) and _flippers.is_target_disabled(other_id),
		"Only the descending target is released after gravity")
	_check(not first.native_hits.is_empty() and first.native_hits[0] is PinballFlipper,
		"Guard release on a stationary plate keeps standard recovery")
	other.reset()
	_check(not _flippers.is_target_disabled(other_id), "Motion reset releases the target")
	_flippers.disable_target(other.body)
	other.body.free()
	_check(not _flippers.is_target_disabled(other_id), "Deleting a target releases its guard")
	first.body.free()


func _test_native_then_sweep() -> void:
	_main.reset_ball()
	var motion := _make_mover(6.0)
	motion.body.collision_mask = 8
	var table := _flippers.items[0] as TableFlipper
	var points := table.world_polygon_at(table.global_transform)
	var normal := (points[1] - points[0]).orthogonal().normalized()
	var start := points[0].lerp(points[1], 0.55) + normal * 23.0
	_place_mover(motion, 6.0, start, normal * 1800.0)
	var wall := _make_wall(start + normal * 14.0, normal, 8)
	await physics_frame
	var delta := 1.0 / 60.0
	var swings := _flippers.plan_motion(true, false)
	_flippers.advance(delta, true, false)
	motion.advance(delta, swings)
	var hit := _first(motion)
	if not hit.is_empty():
		_check(not motion.native_hits.is_empty() and motion.native_hits[0] == wall
			and hit.native_contacts_before == 1, "Native wall contact comes before the rising plate")
		var native_time := motion.native_travel.dot(normal) / 1800.0
		var next := swings[0].sweep(start + motion.native_travel, hit.incoming, 6.0,
			native_time, delta - native_time, _flippers.power_equalization)
		_check(not next.is_empty() and absf(next.time - hit.time) < 0.000001
			and (next.point as Vector2).distance_to(hit.point) < 0.001,
			"Sweep resumes from the native contact's consumed time and corrected position")
		_check(hit.get("normal_separation", false),
			"A sweep after a wall reflection still recognizes a new geometric contact")
	motion.body.free()
	wall.free()


func _test_prediction() -> void:
	var ball := _main.ball
	var guide := _main.get_node("Playfield/ShotGuide")
	_main.reset_ball()
	ball.gravity = 0.0
	for side: int in 2:
		var table := _flippers.items[side] as TableFlipper
		var points := table.world_polygon_at(table.global_transform)
		var normal := (points[1] - points[0]).orthogonal().normalized()
		var start := points[0].lerp(points[1], 0.55) + normal * (ball.radius + 1.0)
		var velocity := -normal * 300.0
		_main.place_ball(start, velocity)
		var left := _flippers.items[0].global_transform
		var right := _flippers.items[1].global_transform
		var guide_velocity: Vector2 = _main.predict_shot()
		guide._physics_process(STEP)
		_check(guide_velocity != Vector2.ZERO and guide._shot_velocity == guide_velocity,
			"Shot guide shows a directed shot for either flipper")
		_check(ball.global_position == start and ball.velocity == velocity
			and left == _flippers.items[0].global_transform and right == _flippers.items[1].global_transform
			and not _flippers.is_target_disabled(ball.get_instance_id())
			and ball.get_collision_exceptions().is_empty(), "Prediction leaves the live state unchanged")

		_flippers.disable_target(ball)
		guide._physics_process(STEP)
		_check(guide._shot_velocity == Vector2.ZERO
			and _flippers.is_target_disabled(ball.get_instance_id()), "Guarded prediction stays hidden and preserves guard")
		_main.place_ball(start, velocity)
		_flippers.advance(0.03, true, true)
		_check(_main.predict_shot() == Vector2.ZERO, "Held flippers have no shot to preview")
		_main.reset_ball()

	var table := _flippers.items[0] as TableFlipper
	var underside := Vector2((table.fixed_left + table.fixed_right) * 0.5, table.fixed_bottom)
	_main.place_ball(underside + Vector2.DOWN * (ball.radius + 1.0), Vector2.UP * 300.0)
	_check(_main.predict_shot() == Vector2.ZERO, "Underside reflection is hidden")
	_main.place_ball(Vector2(table.fixed_right + ball.radius + 1.0, table.fixed_bottom - 12.0),
		Vector2.LEFT * 300.0)
	_check(_main.predict_shot() == Vector2.ZERO, "Side reflection is hidden")
	_main.place_ball(Vector2(960, 640), Vector2.ZERO)
	_check(_main.predict_shot() == Vector2.ZERO, "Unreachable ball is hidden")
	_main.place_ball(Vector2(960, 395), Vector2.DOWN * 960.0)
	_check(_main.predict_shot() == Vector2.ZERO, "Bumper-only path is hidden")

	ball.radius = 6.0
	_main.place_ball(Vector2(922.766846, 1046.035522), Vector2(-230.652542, 191.831711))
	_check(_main.predict_shot() != Vector2.ZERO, "Tip fixture predicts an outward shot")
	_flippers.root_angle = -70.0
	_flippers.tip_angle = -70.0
	_check(_main.predict_shot() == Vector2.ZERO, "An inward direction hides the powered fallback")
	_flippers.root_angle = -20.0
	_flippers.tip_angle = 40.0
	_main.reset_ball()


func _test_prediction_blockers() -> void:
	var ball := _main.ball
	ball.radius = 24.0
	var table := _flippers.items[0] as TableFlipper
	var points := table.world_polygon_at(table.global_transform)
	var normal := (points[1] - points[0]).orthogonal().normalized()
	var point := points[0].lerp(points[1], 0.55)
	var start := point + normal * 75.0
	var velocity := -normal * 2600.0
	_main.place_ball(start, velocity)
	_check(_main.predict_shot() != Vector2.ZERO, "Blocker fixture has a shot on an open path")

	var wall := _make_wall(start - normal * 34.0, normal, 2)
	await physics_frame
	_check(_main.predict_shot() == Vector2.ZERO, "A wall reached before the flipper hides the guide")
	wall.free()

	var bumper := _main.get_node("Playfield/Bumper") as PinballBumper
	var old_position := bumper.global_position
	bumper.radius = 18.0
	bumper.global_position = start - normal * 45.0
	await physics_frame
	_check(_main.predict_shot() == Vector2.ZERO, "A bumper reached before the flipper hides the guide")
	bumper.global_position = old_position

	var enemy := preload("res://enemies/enemy.tscn").instantiate() as Enemy
	_main.get_node("Enemies").add_child(enemy)
	enemy.radius = 12.0
	enemy.collision_layer = 4
	enemy.global_position = start - normal * 39.0
	await physics_frame
	_check(_main.predict_shot() == Vector2.ZERO, "An Enemy reached before the flipper hides the guide")
	enemy.free()
	_check(_main.predict_shot() != Vector2.ZERO, "Removing the blockers restores the directed shot")


func _make_wall(point: Vector2, normal: Vector2, layer: int) -> StaticBody2D:
	var wall := StaticBody2D.new()
	wall.collision_layer = layer
	var shape := CollisionShape2D.new()
	var segment := SegmentShape2D.new()
	segment.a = normal.orthogonal() * 18.0
	segment.b = -segment.a
	shape.shape = segment
	wall.add_child(shape)
	_main.get_node("Playfield").add_child(wall)
	wall.global_position = point
	return wall


func _make_mover(radius: float) -> MotionProbe:
	var body := CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	var collision := CollisionShape2D.new()
	collision.shape = CircleShape2D.new()
	body.add_child(collision)
	_main.get_node("Playfield").add_child(body)
	var motion := MotionProbe.new(body)
	motion.gravity = 0.0
	motion.max_speed = 3600.0
	motion.flippers = _flippers
	motion.boundary = _main.boundary
	_place_mover(motion, radius, Vector2(960, 650), Vector2.ZERO)
	return motion


func _place_mover(motion: MotionProbe, radius: float, position: Vector2, velocity: Vector2) -> void:
	motion.reset()
	motion.radius = radius
	motion.body.get_child(0).shape.radius = radius
	motion.body.global_position = position
	motion.body.velocity = velocity
	motion.swept_hits.clear()
	motion.native_hits.clear()


func _advance_mover(motion: MotionProbe, delta: float, left: bool, right: bool) -> void:
	var swings := _flippers.plan_motion(left, right)
	_flippers.advance(delta, left, right)
	motion.advance(delta, swings)


func _first(motion: MotionProbe) -> Dictionary:
	_check(not motion.swept_hits.is_empty(), "Recorded fixture has an independent sweep contact")
	return motion.swept_hits[0] if not motion.swept_hits.is_empty() else {}


func _check_first(
	motion: MotionProbe, point: Vector2, normal: Vector2, outgoing: Vector2, correction: Vector2,
) -> void:
	var hit := _first(motion)
	if hit.is_empty():
		return
	_check((hit.point as Vector2).distance_to(point) < 0.001
		and (hit.normal as Vector2).distance_to(normal) < 0.001, "First contact matches the recorded point and normal")
	_check((hit.outgoing as Vector2).distance_to(outgoing) < 0.01, "First velocity matches the recorded response")
	_check((hit.correction as Vector2).distance_to(correction) < 0.003,
		"First correction matches the recorded direction and distance")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


class MotionProbe extends PinballMotion:
	var swept_hits: Array[Dictionary] = []
	var native_hits: Array[Object] = []
	var native_travel: Vector2

	func apply_swept_contact(hit: Dictionary) -> void:
		var start := body.global_position
		var incoming := body.velocity
		super.apply_swept_contact(hit)
		hit.incoming = incoming
		hit.outgoing = body.velocity.limit_length(max_speed)
		hit.correction = body.global_position - (start + incoming * hit.time)
		hit.guarded = flippers.is_target_disabled(body.get_instance_id())
		hit.native_contacts_before = native_hits.size()
		swept_hits.append(hit)

	func resolve_contact(collision: KinematicCollision2D) -> void:
		if native_hits.is_empty():
			native_travel = collision.get_travel()
		native_hits.append(collision.get_collider())
		super.resolve_contact(collision)
