extends SceneTree

const Motion = preload("res://pinball/motion.gd")

var checks: int = 0
var failures: int = 0
var _main: PinballLab


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_main = load("res://main/main.tscn").instantiate() as PinballLab
	(_main.get_node("EnemySpawner") as EnemySpawner).enabled = false
	root.add_child(_main)
	_main.set_physics_process(false)
	await physics_frame
	await physics_frame
	_check(_main.flippers.pass_until_descending, "Main must enable guard 3")
	for item: PinballFlipper in _main.flippers.items:
		var fixed := item as TableFlipper
		_check(fixed != null and fixed.extra_thickness == 48, "Main fixed shape is missing")
		_check(fixed.get_node_or_null("CollisionPreview") == null, "Debug collision fill leaked into main")
		var before := fixed.world_polygon_at(fixed.global_transform)
		fixed.advance(0.01, true, 18, 600, 420)
		var after := fixed.world_polygon_at(fixed.global_transform)
		for index in 4:
			_check(is_equal_approx(before[index].x, after[index].x), "Flipping changed fixed X bounds")
		_check(before[2] == after[2] and before[3] == after[3], "Flipping moved the fixed bottom")
		var inside := after[0].lerp(after[1], 0.65) + Vector2.DOWN * 5
		var hit := fixed._contact_at(inside, 24, fixed.global_transform, 0, 0)
		var correction := fixed.separation_for(inside, 24, hit, 0.15)
		_check(correction.x == 0 and correction.y < 0, "Overlap correction must point upward")
		_check(fixed._contact_at(inside + correction, 24, fixed.global_transform, 0, 0).is_empty(),
			"Upward correction left the circle embedded")
	_main.reset_ball()
	await _test_generic_motion()
	await _test_multibody()
	await _test_main_shot()
	_main.free()
	print("Migration checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _make_mover(radius: float, position: Vector2, velocity: Vector2) -> Dictionary:
	var body := CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collision.shape = shape
	body.add_child(collision)
	_main.get_node("Playfield").add_child(body)
	body.global_position = position
	body.velocity = velocity
	var motion := Motion.new(body)
	motion.radius = radius
	motion.gravity = 0
	motion.max_speed = 3600
	motion.boundary = _main.boundary
	motion.flippers = _main.flippers
	return {"body": body, "motion": motion}


func _test_generic_motion() -> void:
	_main.reset_ball()
	var fixed := _main.flippers.items[0] as TableFlipper
	var polygon := fixed.world_polygon_at(fixed.global_transform)
	var target := _make_mover(24, polygon[0].lerp(polygon[1], 0.9) + Vector2.UP * 28,
		Vector2(0, 300))
	var other := _make_mover(6, Vector2(960, 400), Vector2.ZERO)
	await physics_frame
	for step in 12:
		var swings := _main.flippers.plan_motion(true, false)
		_main.flippers.advance(PinballLab.STEP, true, false)
		target.motion.advance(PinballLab.STEP, swings)
		other.motion.advance(PinballLab.STEP, swings)
	_check(target.body.get_script() == null, "Generic test must not use a ball or enemy script")
	_check(target.body.velocity.y < 0, "Common movement did not produce an upward shot")
	var id: int = target.body.get_instance_id()
	_check(_main.flippers.is_target_disabled(id), "Flipper manager did not own the generic target state")
	_check(not _main.flippers.is_target_disabled(other.body.get_instance_id()), "One shot disabled another target")
	for item: PinballFlipper in _main.flippers.items:
		_check(item.collision_layer == 2, "Per-target guard changed the global flipper layer")
	# Upward motion must pass through both flippers without recovery or reflection.
	target.body.global_position = polygon[0].lerp(polygon[2], 0.5)
	target.body.velocity = Vector2(0, -600)
	var before: Vector2 = target.body.global_position
	target.motion.advance(PinballLab.STEP)
	_check(target.body.global_position.distance_to(before + Vector2.UP * 600 * PinballLab.STEP) < 0.001,
		"Suppressed target still collides or recovers against a flipper")
	_check(target.body.get_collision_exceptions().is_empty(), "Guard leaked collision exceptions after a step")
	# The gravity-adjusted velocity, rather than the previous velocity, releases it.
	target.body.global_position = Vector2(960, 400)
	target.body.velocity = Vector2(0, -1)
	target.motion.gravity = 1500
	target.motion.advance(PinballLab.STEP)
	_check(not _main.flippers.is_target_disabled(id), "Descending target did not regain collision")
	_main.flippers.disable_target(target.body)
	target.body.free()
	_check(not _main.flippers.is_target_disabled(id), "Freed target retained manager state")
	other.body.free()


func _test_multibody() -> void:
	_main.reset_ball()
	var fixed := _main.flippers.items[0] as TableFlipper
	var polygon := fixed.world_polygon_at(fixed.global_transform)
	var targets: Array[Dictionary] = []
	for index in 20:
		var radius: float = [6.0, 24.0, 36.0][index % 3]
		targets.append(_make_mover(radius, polygon[0].lerp(polygon[1], 0.65)
			+ Vector2.UP * (radius + 4), Vector2(0, 300)))
	await physics_frame
	for step in 12:
		var swings := _main.flippers.plan_motion(true, false)
		_main.flippers.advance(PinballLab.STEP, true, false)
		for target: Dictionary in targets:
			target.motion.advance(PinballLab.STEP, swings)
	for target: Dictionary in targets:
		_check(_main.flippers.is_target_disabled(target.body.get_instance_id()), "Multibody state missing")
		_check(target.body.velocity.y < 0, "Multibody shot did not travel upward")
		_check(target.body.get_collision_exceptions().is_empty(), "Multibody collision exceptions leaked")
	targets[0].body.velocity = Vector2(0, 300)
	targets[0].motion.advance(PinballLab.STEP)
	_check(not _main.flippers.is_target_disabled(targets[0].body.get_instance_id()), "One target did not release")
	_check(_main.flippers.is_target_disabled(targets[1].body.get_instance_id()), "One release cleared all targets")
	for target: Dictionary in targets:
		target.body.free()


func _test_main_shot() -> void:
	_main.reset_ball()
	var fixed := _main.flippers.items[0] as TableFlipper
	var polygon := fixed.world_polygon_at(fixed.global_transform)
	_main.place_ball(polygon[0].lerp(polygon[1], 0.92) + Vector2.UP * 28, Vector2(0, 300))
	_check(_main.predict_shot().length() > 0, "Main shot preview did not use the new shape")
	Input.action_press(&"pinball_left")
	Input.action_press(&"pinball_right")
	_main.advance(0.06)
	Input.action_release(&"pinball_left")
	Input.action_release(&"pinball_right")
	_check(_main.flippers.is_target_disabled(_main.ball.get_instance_id()), "Main ball did not start guard 3")
	_check(_main.predict_shot() == Vector2.ZERO, "Prediction remains visible during guard 3")
	_check(_main.ball.velocity.y < 0, "Main tip shot lost its upward motion")
	_main.reset_ball()
	_check(not _main.flippers.is_target_disabled(_main.ball.get_instance_id()), "Ball reset retained guard state")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
