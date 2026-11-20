extends "res://experiments/flippers/tests/shot_direction_test.gd"

var _current_cases: Array[Dictionary] = []


func _run() -> void:
	var preview := _make_preview(true)
	await physics_frame
	await physics_frame
	for kind: String in ["empty", "enemy"]:
		for ratio: float in [0.05, 0.15, 0.30, 0.50, 0.70, 0.90, 0.99]:
			for gap: float in [3.0, 12.0, 36.0, 72.0]:
				for horizontal_offset: float in [-36.0, 0.0, 36.0]:
					if kind == "empty" and (gap != 3 or horizontal_offset != 0):
						continue
					await _current_case(preview, kind, ratio, gap, horizontal_offset)
	var output := {"cases": _current_cases, "checks": checks, "failures": failures,
		"flipper_speed": 600, "swing_angle": 18, "tip_angle": 40,
		"root_angle": -20, "gravity": 1500, "ball_radius": 24, "enemy_radius": 30}
	var file := FileAccess.open("res://experiments/flippers/evidence/current_guard.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print("Current-setting cases: ", _current_cases.size(), "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _current_case(preview: Preview, kind: String, ratio: float, gap: float, offset_x: float) -> void:
	var guard := preview.flippers as Guard
	guard.raise_speed = 600
	guard.swing_angle = 18
	guard.tip_angle = 40
	guard.root_angle = -20
	guard.reset_stats()
	preview.reset_ball()
	var ball := preview.ball as Probe
	ball.first_shot.clear()
	ball.embedded_releases.clear()
	ball.opposite_normal_changes.clear()
	ball.opposite_shots.clear()
	ball.external_since_shot = 0
	ball.shots = 0
	ball.damage = 50.0
	var fixed := guard.items[0] as FixedFlipper
	var polygon := fixed.world_polygon_at(fixed.global_transform)
	var top := polygon[0].lerp(polygon[1], ratio)
	ball.reset_at(top + Vector2.UP * (ball.radius + 4), Vector2(0, 300))
	var enemy: Enemy
	if kind == "enemy":
		enemy = load("res://enemies/enemy.tscn").instantiate() as Enemy
		enemy.position = ball.global_position + Vector2(offset_x, -(ball.radius + 30 + gap))
		preview.get_node("Playfield").add_child(enemy)
		enemy.prepare(enemy.grow_duration)
		ball.collision_mask |= 4
	else:
		ball.collision_mask = 2
	await physics_frame
	await physics_frame
	var initial_enemy_position := enemy.global_position if enemy != null else Vector2.ZERO
	var external_at_release := 0
	var elapsed := 0.0
	for frame in 60:
		var remaining := 1.0 / 60.0
		while remaining > 0.000001:
			var step := minf(minf(STEP, remaining), guard.motion_step_limit(ball.radius, true, true))
			ball.simulation_time = elapsed
			var swings := guard.plan_motion(true, true)
			guard.advance(step, true, true)
			if is_instance_valid(enemy):
				enemy.prepare(step)
				enemy.advance(step)
			var releases_before := ball.embedded_releases.size()
			ball.advance(step, swings)
			if ball.embedded_releases.size() > releases_before:
				external_at_release = ball.external_since_shot
			remaining -= step
			elapsed += step
		await physics_frame
	_check(is_finite(ball.global_position.y), "Invalid ball position")
	var entry := {"kind": kind, "ratio": ratio, "gap": gap, "offset_x": offset_x,
		"enemy_position": Probe._vector(initial_enemy_position), "first_shot": ball.first_shot.duplicate(true),
		"embedded_releases": ball.embedded_releases.duplicate(true),
		"external_contacts": ball.external_since_shot, "external_at_release": external_at_release,
		"shots": ball.shots, "max_separation": ball.max_separation,
		"enemy_active": enemy.active if is_instance_valid(enemy) else false}
	_current_cases.append(entry)
	if is_instance_valid(enemy):
		enemy.free()
	if _current_cases.size() % 30 == 0:
		print("Current-setting cases completed: ", _current_cases.size())
