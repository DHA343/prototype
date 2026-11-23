extends "res://experiments/flippers/tests/stable_audit.gd"


func _run() -> void:
	_config = METHODS[4]
	_make_main(false)
	await physics_frame
	await physics_frame
	_reset_integration()
	_main.ball._sync_motion()
	var actor := _new_enemy(Vector2(960, 500))
	var recorder := _main.ball._motion as Stable
	recorder._elapsed = 0.0
	_main.ball.global_position = Vector2.ZERO
	var inputs: Array[Dictionary] = [
		{"center": Vector2(100, 0), "ball": Vector2(100, 0), "enemy": Vector2.ZERO, "time": .46},
		{"center": Vector2(100, 0), "ball": Vector2.ZERO, "enemy": Vector2(-100, 0), "time": .46},
		{"center": Vector2(100, 0), "ball": Vector2(100, 0), "enemy": Vector2(100, 0), "time": -1.0},
		{"center": Vector2(100, 0), "ball": Vector2(100, 0), "enemy": Vector2(200, 0), "time": -1.0},
		{"center": Vector2(100, 0), "ball": Vector2(10000, 0), "enemy": Vector2.ZERO, "time": .0046},
		{"center": Vector2(100, 54), "ball": Vector2(100, 0), "enemy": Vector2.ZERO, "time": 1.0},
	]
	for input: Dictionary in inputs:
		recorder.enemy_paths.clear()
		recorder.enemy_paths.append({"body": actor, "start": input.center,
			"end": input.center + input.enemy, "velocity": input.enemy})
		_main.ball.velocity = input.ball
		var result := recorder._enemy_contact(1.0)
		_check(result.is_empty() == (input.time < 0.0), "Relative circle contact classification changed")
		if not result.is_empty():
			_check(absf(result.time - input.time) < 0.000001, "Relative circle contact time changed")
	_main.ball.damage = 0.0
	_main.ball.damage_per_speed = 0.0
	_main.ball.knockback = 0.0
	_main.ball.knockback_per_speed = 0.0
	for incoming: Vector2 in [Vector2(100, 20), Vector2(-100, 20), Vector2(0, 300)]:
		for normal: Vector2 in [Vector2.LEFT, Vector2.UP]:
			for surface: Vector2 in [Vector2.ZERO, Vector2(30, -20)]:
				_main.ball.velocity = incoming
				var expected := PinballBall.reflected_velocity(incoming, normal, actor.restitution, surface)
				recorder._native_response(actor, Vector2.ZERO, normal, surface)
				_check(_main.ball.velocity.distance_to(expected) < 0.001,
					"Relative response changed restitution or surface speed")
	actor.free()
	_reset_integration()
	recorder = _main.ball._motion as Stable
	_main.flippers.advance(18.0 / 600.0, true, true)
	var polygon := (_main.flippers.items[0] as TableFlipper).world_polygon_at(
		_main.flippers.items[0].global_transform)
	_main.ball.reset_at(polygon[0].lerp(polygon[1], .5) + Vector2.DOWN * 12, Vector2(100, 200))
	_main.ball.gravity = 0.0
	_main.ball.advance(1.0 / 60.0, [])
	var zero_recoveries := 0
	for event: Dictionary in recorder.native_geometry:
		if event.raw_safe_fraction == 0:
			_check(event.time_ms == event.before_time_ms, "Recovery consumed physical time")
			zero_recoveries += 1
	_check(zero_recoveries > 0, "Raw recovery fixture did not exercise zero-time contact")
	_config = METHODS[10]
	var conformance := await _enemy_conformance()
	_check(conformance.cases == 48, "Enemy segment conformance corpus changed")
	_main.free()
	_write("stable_contracts.json", {"checks": _checks, "failures": _failures,
		"circle_cases": inputs.size(), "response_cases": 12, "zero_time_recoveries": zero_recoveries,
		"enemy_conformance": conformance})
	print("Stability contracts: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
