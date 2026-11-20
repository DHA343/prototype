extends SceneTree

const Counter = preload("res://pinball/tests/counting_ball.gd")
const Motion = preload("res://pinball/motion.gd")

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var main := load("res://main/main.tscn").instantiate() as PinballLab
	var ball := main.get_node("Playfield/Ball") as PinballBall
	ball.set_script(Counter)
	ball.radius = 6
	ball.gravity = 1500
	ball.max_speed = 3600
	(main.get_node("EnemySpawner") as EnemySpawner).enabled = false
	root.add_child(main)
	main.set_physics_process(false)
	await physics_frame
	await physics_frame
	main.flippers.raise_speed = 1440
	Input.action_press(&"pinball_left")
	main.advance(1.0 / 60.0)
	Input.action_release(&"pinball_left")
	_check((ball as Counter).updates == 1, "Main still subdivides the physical update")
	_check(is_equal_approx((ball as Counter).last_delta, 1.0 / 60.0), "Main changed the frame duration")
	main.advance(1.0 / 30.0)
	_check((ball as Counter).updates == 2, "Main still adds radius-dependent physical updates")
	main.flippers.raise_speed = 600
	main.reset_ball()
	var body := CharacterBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 2
	var collision := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24
	collision.shape = circle
	body.add_child(collision)
	main.get_node("Playfield").add_child(body)
	var motion := Motion.new(body)
	motion.radius = 24
	motion.gravity = 0
	motion.max_speed = 3600
	motion.boundary = main.boundary
	motion.flippers = main.flippers
	var hits := [0]
	motion.contact_recorded = func(_point: Vector2, _normal: Vector2) -> void: hits[0] += 1
	await physics_frame
	for strike in 2:
		var item := main.flippers.items[0] as TableFlipper
		var polygon := item.world_polygon_at(item.global_transform)
		body.global_position = polygon[0].lerp(polygon[1], 0.65) + Vector2.UP * 24.5
		body.velocity = Vector2(0, 300)
		var swings := main.flippers.plan_motion(true, false)
		main.flippers.advance(1.0 / 240.0, true, false)
		motion.advance(1.0 / 240.0, swings)
		_check(item.is_rising(), "Re-hit fixture is not in the same upward stroke")
		_check(main.flippers.is_target_disabled(body.get_instance_id()), "A returned ball could not start guard 3 again")
		_check(body.velocity.y < 0, "A returned ball was not struck upward")
	_check(hits[0] == 2, "Per-flipper hit history still blocks the second shot")
	body.free()
	main.free()
	print("Minimal checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
