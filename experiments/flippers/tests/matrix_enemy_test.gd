extends "res://experiments/flippers/tests/method_matrix_test.gd"

const EnemyProbe = preload("res://experiments/flippers/tests/matrix_enemy_probe.gd")


func _run() -> void:
	_preview = _make_preview(EnemyProbe)
	await physics_frame
	await physics_frame
	var cases: Array[Dictionary] = []
	for configuration: String in ["legacy", "no_split_iterative", "end_response"]:
		for ratio: float in [0.05, 0.15, 0.30, 0.50, 0.70, 0.90, 0.99]:
			for gap: float in [3, 12, 36, 72]:
				for offset_x: float in [-36, 0, 36]:
					cases.append(await _enemy_case(configuration, ratio, gap, offset_x))
	var file := FileAccess.open("res://experiments/flippers/evidence/matrix_enemy.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": cases, "checks": checks, "failures": failures}, "\t"))
	print("Matrix enemy checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _enemy_case(configuration: String, ratio: float, gap: float, offset_x: float) -> Dictionary:
	var split := configuration == "legacy"
	_reset_pose(false, 48, 18, 600)
	(_preview.flippers as Guard).reset_stats()
	for item: PinballFlipper in _preview.flippers.items:
		item.collision_layer = 2
	var ball := _preview.ball as EnemyProbe
	ball.iterative = configuration != "end_response"
	ball.final_response = configuration == "end_response"
	ball.rotation_sweep = true
	ball.guard_enabled = true
	ball.collision_mask = 6
	ball.damage = 50
	ball.contacts = 0
	ball.shots = 0
	ball.updates = 0
	ball.cap_steps = 0
	ball.internal_releases = 0
	ball.shots_on_release = 0
	ball.max_end_correction = 0
	var fixed := _preview.flippers.items[0] as Fixed
	var points := fixed.world_polygon_at(fixed.global_transform)
	ball.reset_at(points[0].lerp(points[1], ratio) + Vector2.UP * 28, Vector2(0, 300))
	var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
	enemy.position = ball.global_position + Vector2(offset_x, -(24 + 30 + gap))
	_preview.get_node("Playfield").add_child(enemy)
	enemy.prepare(enemy.grow_duration)
	await physics_frame
	var below := false
	var max_excess_move := 0.0
	for frame in 60:
		var remaining := FRAME
		while remaining > 0.000001:
			var step := remaining
			if split:
				step = minf(minf(step, Preview.STEP), _preview.flippers.motion_step_limit(24, true, true))
			var swings := _preview.flippers.plan_motion(true, true)
			_preview.flippers.advance(step, true, true)
			if is_instance_valid(enemy):
				enemy.prepare(step)
				enemy.advance(step)
			var before := ball.global_position
			ball.advance(step, swings)
			max_excess_move = maxf(max_excess_move,
				ball.global_position.distance_to(before) - ball.max_speed * step)
			for item: PinballFlipper in _preview.flippers.items:
				var quad := item as Fixed
				var y := quad.fixed_bottom + 24
				if before.y <= y and ball.global_position.y > y:
					var fraction := (y - before.y) / (ball.global_position.y - before.y)
					var x := lerpf(before.x, ball.global_position.x, fraction)
					below = below or (x > quad.fixed_left + 24 and x < quad.fixed_right - 24)
			remaining -= step
		await physics_frame
	_check(is_finite(ball.global_position.y), "Invalid near-enemy response")
	var result := {"configuration": configuration, "split": split,
		"ratio": ratio, "gap": gap, "offset_x": offset_x,
		"internal_releases": ball.internal_releases, "shots_on_release": ball.shots_on_release,
		"below_flipper": below, "max_correction": maxf(ball.max_separation, ball.max_end_correction),
		"shots": ball.shots, "body_updates": ball.updates, "contacts": ball.contacts,
		"cap_steps": ball.cap_steps}
	result.max_excess_move_px = max_excess_move
	if is_instance_valid(enemy):
		enemy.free()
	return result
