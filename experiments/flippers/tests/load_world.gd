extends Node

const LoadFlipper = preload("res://experiments/flippers/tests/load_flipper.gd")
const LoadMotion = preload("res://experiments/flippers/tests/load_motion.gd")
const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")
const MAIN: PackedScene = preload("res://main/main.tscn")
const ENEMY: PackedScene = preload("res://enemies/enemy.tscn")

var main: PinballLab
var balls: Array[PinballBall] = []
var config: Dictionary
var refined: bool = false
var detailed: bool = false
var starts: Array[Vector2] = []
var initial_velocities: Array[Vector2] = []
var respawns: Array[float] = []
var enemy_starts: Array[Vector2] = []
var removed: Dictionary = {"killed": 0, "escaped": 0}
var guide: Node2D


func setup(settings: Dictionary, use_refined: bool, profile: bool) -> void:
	config = settings
	refined = use_refined
	detailed = profile
	main = MAIN.instantiate() as PinballLab
	main.spawner = main.get_node("EnemySpawner") as EnemySpawner
	main.spawner.enabled = false
	main.set_physics_process(false)
	guide = main.get_node("Playfield/ShotGuide") as Node2D
	guide.set_physics_process(false)
	if detailed:
		for name: String in ["LeftFlipper", "RightFlipper"]:
			var item := main.get_node("Playfield/Flippers/" + name) as TableFlipper
			var pivot := item.pivot_socket
			var tip := item.tip_socket
			var side := item.side
			var thickness := item.extra_thickness
			item.set_script(LoadFlipper)
			item.pivot_socket = pivot
			item.tip_socket = tip
			item.side = side
			item.extra_thickness = thickness
	add_child(main)
	# Script callbacks become enabled when the instance enters the tree.
	main.set_physics_process(false)
	guide.set_physics_process(false)
	assert(not main.is_physics_processing() and not guide.is_physics_processing(),
		"Automatic updates must be disabled before running the audit")
	main.launcher._random.seed = 20261122
	if int(config.balls) == 0:
		main.ball.active = false
		main.ball.visible = false
		main.ball.collision_layer = 0
		main.ball.collision_mask = 0
		(main.ball.get_node("CollisionShape2D") as CollisionShape2D).disabled = true
	for index in int(config.balls):
		var ball := main.ball
		if index > 0:
			ball = PinballBall.new()
			var collision := CollisionShape2D.new()
			collision.name = "CollisionShape2D"
			collision.shape = CircleShape2D.new()
			ball.add_child(collision)
			main.get_node("Playfield").add_child(ball)
			ball.boundary = main.boundary
			ball.flippers = main.flippers
			ball.radius = main.ball.radius
			ball.gravity = main.ball.gravity
			ball.max_speed = main.ball.max_speed
			ball.damage = main.ball.damage
			ball.hit_sound = main.ball.hit_sound
			ball.collision_mask = 6
			ball.sound_requested.connect(main._sound.request)
		if detailed:
			var motion := LoadMotion.new(ball)
			motion.refined = refined
			motion.native_response = ball._resolve_contact
			motion.contact_recorded = ball._record_contact
			ball._motion = motion
		elif refined:
			ball._motion = RefinedMotion.new(ball)
			ball._motion.native_contact = ball._resolve_contact
			ball._motion.contact_recorded = ball._record_contact
		var random := RandomNumberGenerator.new()
		random.seed = 11000 + index
		var start := Vector2(random.randf_range(610, 1310), random.randf_range(180, 760))
		if index == 0:
			start = Vector2(780, 540)
		starts.append(start)
		respawns.append(0.0)
		ball.reset_at(start, Vector2(random.randf_range(-400, 400), random.randf_range(0, 500)))
		initial_velocities.append(ball.velocity)
		balls.append(ball)


func settle_balls() -> void:
	for index in balls.size():
		var ball := balls[index]
		var query := PhysicsShapeQueryParameters2D.new()
		var circle := CircleShape2D.new()
		circle.radius = ball.radius + 0.1
		query.shape = circle
		query.collision_mask = 6
		var random := RandomNumberGenerator.new()
		random.seed = 11000 + index
		for attempt in 64:
			query.transform = Transform2D(0.0, starts[index])
			if ball.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
				break
			starts[index] = Vector2(random.randf_range(610, 1310), random.randf_range(180, 760))
		query.transform = Transform2D(0.0, starts[index])
		assert(ball.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty(),
			"Ball fixture starts overlapping world geometry")
		ball.reset_at(starts[index], initial_velocities[index])


func reset_episode() -> void:
	main.flippers.reset_input()
	for enemy: Enemy in main.enemies:
		enemy.free()
	main.enemies.clear()
	for projectile: Projectile in main.launcher._flights:
		projectile.free()
	main.launcher._flights.clear()
	main.launcher._pending_shots.clear()
	main.launcher._random.seed = 20261122
	removed = {"killed": 0, "escaped": 0}
	enemy_starts.clear()
	for index in balls.size():
		balls[index].reset_at(starts[index], initial_velocities[index])
		respawns[index] = 0.0


func populate() -> bool:
	var random := RandomNumberGenerator.new()
	random.seed = 20261122
	for index in int(config.enemies):
		var point := Vector2.ZERO
		var clear := false
		for attempt in 20000:
			point = Vector2(random.randf_range(550, 1370), random.randf_range(150, 720))
			if main._can_spawn_enemy(point, 30.0):
				clear = true
				break
		if not clear:
			push_error("Could not place the requested enemy count")
			return false
		var enemy := ENEMY.instantiate() as Enemy
		enemy.position = point
		main.get_node("Enemies").add_child(enemy)
		main._on_enemy_spawned(enemy)
		enemy.removed.connect(_on_removed)
		enemy.prepare(enemy.grow_duration)
		enemy_starts.append(point)
	assert(main.enemies.size() == int(config.enemies), "Enemy fixture count differs")
	return main.enemies.size() == int(config.enemies)


func tick(delta: float, frame: int) -> Dictionary:
	var counters := {"contacts": 0, "caps": 0, "discarded_us": 0.0, "max_correction_px": 0.0,
		"detection_us": 0, "sweep_queries": 0, "extra_checks": 0, "native_queries": 0,
		"ball_geometry_checks": 0, "guide_geometry_checks": 0, "separation_checks": 0,
		"separation_us": 0, "active_balls": 0, "enemies_start": main.enemies.size()}
	if detailed:
		for item: LoadFlipper in main.flippers.items:
			item.clear_counts()
	var times := {}
	var began := Time.get_ticks_usec()
	var clock := began
	main.routes.refresh()
	clock = _stage(times, "routes_us", clock)
	var left: bool = config.moving and fmod(frame * delta, 0.55) < 0.08
	var right: bool = config.moving and fmod(frame * delta + 0.275, 0.55) < 0.08
	var plans := main.flippers.plan_motion(left, right)
	main.flippers.advance(delta, left, right)
	clock = _stage(times, "flippers_us", clock)
	for enemy: Enemy in main.enemies:
		enemy.prepare(delta)
	clock = _stage(times, "enemy_prepare_us", clock)
	main.crowd.calculate(main.enemies, delta, main.boundary.exit_target())
	clock = _stage(times, "crowd_us", clock)
	for enemy: Enemy in main.enemies:
		enemy.advance(delta)
	clock = _stage(times, "enemy_move_us", clock)
	for index in balls.size():
		var ball := balls[index]
		if ball.active:
			counters.active_balls += 1
			ball.advance(delta, plans)
			if detailed:
				var motion := ball._motion as LoadMotion
				counters.contacts += motion.events.size()
				counters.caps += int(motion.discarded_seconds > 0.0)
				counters.discarded_us += motion.discarded_seconds * 1000000.0
				counters.detection_us += motion.detection_us
				counters.sweep_queries += motion.sweep_queries
				counters.extra_checks += motion.extra_checks
				counters.native_queries += motion.native_queries
				for event: Dictionary in motion.events:
					counters.max_correction_px = maxf(counters.max_correction_px, event.correction_px)
			if main.boundary.to_local(ball.global_position).y > main.boundary.bottom + 120.0:
				ball.active = false
				ball.visible = false
				respawns[index] = main.respawn_delay
		else:
			respawns[index] -= delta
			if respawns[index] <= 0.0:
				if index == 0:
					main.flippers.reset_input()
				ball.reset_at(starts[index])
	clock = _stage(times, "balls_us", clock)
	if detailed:
		for item: LoadFlipper in main.flippers.items:
			counters.ball_geometry_checks += item.detection_checks
			counters.separation_checks += item.separation_checks
			counters.separation_us += item.separation_us
	for index in range(main.enemies.size() - 1, -1, -1):
		var enemy := main.enemies[index]
		if main.boundary.has_exited(enemy.global_position, enemy.radius):
			enemy.finish(Enemy.ExitReason.ESCAPED)
	main.spawner.advance(delta)
	clock = _stage(times, "exits_spawner_us", clock)
	main.launcher.advance(delta, main.enemies)
	clock = _stage(times, "launcher_us", clock)
	guide.set("_shot_velocity", main.predict_shot())
	guide.queue_redraw()
	clock = _stage(times, "guide_us", clock)
	times["app_us"] = clock - began
	if detailed:
		for item: LoadFlipper in main.flippers.items:
			counters.guide_geometry_checks += item.detection_checks
		counters.guide_geometry_checks -= counters.ball_geometry_checks
	counters["enemies_end"] = main.enemies.size()
	counters["missiles"] = main.launcher._flights.size()
	counters["killed"] = removed.killed
	counters["escaped"] = removed.escaped
	times.merge(counters)
	return times


func outcome() -> Dictionary:
	var positions: Array = []
	for ball: PinballBall in balls:
		positions.append([ball.global_position.x, ball.global_position.y, ball.velocity.x, ball.velocity.y])
	return {"balls": positions, "enemies": main.enemies.size(), "removed": removed.duplicate()}


func _stage(times: Dictionary, name: String, clock: int) -> int:
	var next := Time.get_ticks_usec()
	times[name] = next - clock
	return next


func _on_removed(_enemy: Enemy, reason: Enemy.ExitReason) -> void:
	removed["killed" if reason == Enemy.ExitReason.KILLED else "escaped"] += 1
