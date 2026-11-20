extends SceneTree

const TEST_STEP: float = 1.0 / 240.0

const MAIN: PackedScene = preload("res://main/main.tscn")
const ENEMY: PackedScene = preload("res://enemies/enemy.tscn")

var _lab: PinballLab
var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(17)
	_lab = MAIN.instantiate() as PinballLab
	_lab.get_node("EnemySpawner").enabled = false
	_lab.get_node("Playfield/MissileLauncher").free()
	var layout := Node2D.new()
	layout.name = "Layout"
	var obstacles := Node2D.new()
	obstacles.name = "Obstacles"
	_lab.get_node("Playfield").add_child(layout)
	layout.add_child(obstacles)
	for child: Node in _lab.get_node("Playfield").find_children("*", "", true, false):
		if child is PinballBumper:
			child.hit_sound = null
			child.owner = null
			child.reparent(obstacles, false)
			child.name = "Obstacle" + str(obstacles.get_child_count())
	root.add_child(_lab)
	_lab.set_physics_process(false)
	_lab.ball.gravity = 0.0
	_lab.place_ball(Vector2(1800.0, 90.0))
	await _sync()
	await _test_spawning()
	await _test_routes()
	await _test_crowd_exit()
	await _test_walls_and_crowd()
	await _test_flippers()
	await _test_combat()
	await _test_spawn_clock()
	for failure: String in _failures:
		printerr("FAIL: " + failure)
	print("Enemy checks: %d; failures: %d" % [_checks, _failures.size()])
	_lab.queue_free()
	await process_frame
	quit(0 if _failures.is_empty() else 1)


func _test_spawning() -> void:
	var spawner := _lab.spawner
	var area := spawner.spawn_area
	var area_position := area.global_position
	var area_size := area.size
	_lab.boundary.width += 6.0
	await _sync()
	_check(area.global_position == area_position and area.size == area_size,
		"Spawn rectangle is independent of Boundary geometry")
	spawner.interval = 0.5
	spawner.enabled = true
	_lab.advance(0.49)
	_check(_lab.enemies.is_empty(), "First spawn waits for the configured interval")
	_lab.advance(0.011)
	_check(_lab.enemies.size() == 1, "One enemy spawns at each scheduled time")
	if not _lab.enemies.is_empty():
		var enemy := _lab.enemies[0]
		_check(is_equal_approx(enemy.radius, 30.0), "Default enemy radius is 30 units")
		var shape := (enemy.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
		_check(is_equal_approx(shape.radius, enemy.radius), "Body and hit detection use the same circle")
		_check(is_equal_approx(enemy.current_health, 100.0), "Default HP is 100")
		enemy.finish(Enemy.ExitReason.ESCAPED)
	_lab.advance(0.2)
	_check(_lab.enemies.is_empty(), "Escape does not trigger replacement")
	_lab.advance(0.3)
	_check(_lab.enemies.size() == 1, "The independent periodic schedule continues")
	await _clear()
	area.position = Vector2(1800.0, 120.0)
	_lab.advance(1.5)
	_check(_lab.enemies.is_empty(), "Invalid spawn area skips scheduled attempts")
	area.global_position = area_position
	_lab.advance(0.49)
	_check(_lab.enemies.is_empty(), "Skipped spawns do not accumulate")
	_lab.advance(0.01)
	_check(_lab.enemies.size() == 1, "Only one enemy appears at the next valid scheduled time")
	spawner.enabled = false
	await _clear()


func _test_routes() -> void:
	var start := Vector2(960.0, 120.0)
	var path := _lab.routes.path_from(start, 30.0)
	_check(path.size() >= 3, "Path bends around the central bumper")
	_check(not path.is_empty() and path[path.size() - 1].distance_to(_lab.boundary.exit_target()) < 1.0,
		"Path reaches past the opening")
	var enemy := _add(start)
	var escaped := [0]
	var on_removed := func(_enemy: Enemy, reason: Enemy.ExitReason) -> void:
		if reason == Enemy.ExitReason.ESCAPED:
			escaped[0] += 1
	enemy.removed.connect(on_removed)
	for _frame in 1200:
		_lab.advance(1.0 / 60.0)
		if escaped[0] > 0:
			break
		for child: Node in _lab.get_node("Playfield").find_children("*", "", true, false):
			if child is PinballBumper:
				_check(enemy.global_position.distance_to(child.global_position) >= enemy.radius + child.radius - 0.15,
					"Enemy does not penetrate a bumper while following its path")
	_check(escaped[0] == 1 and _lab.enemies.is_empty(), "Enemy follows the route and disappears through the hole")
	var width := _lab.boundary.opening_width
	_lab.boundary.opening_width = 48.0
	await _sync()
	_check(_lab.routes.path_from(start, 30.0).is_empty(), "A body too wide for the hole has no exit path")
	_lab.boundary.opening_width = width
	await _sync()
	await _clear()


func _test_crowd_exit() -> void:
	for rate: float in [30.0, 60.0, 120.0]:
		_add(Vector2(981.0, 1026.0))
		for row in 4:
			for x: float in [924.0, 996.0]:
				_add(Vector2(x, 720.0 + row * 72.0))
		for _frame in int(rate * 30.0):
			_lab.advance(1.0 / rate)
			if _lab.enemies.is_empty():
				break
		print("Crowd exit at %d Hz remaining: %d" % [rate, _lab.enemies.size()])
		_check(_lab.enemies.is_empty(), "Crowded enemies recover paths and exit at %d Hz" % rate)
		await _clear()


func _test_walls_and_crowd() -> void:
	var boundary := _lab.boundary
	var left := boundary.to_global(Vector2(-boundary.width * 0.5, 600.0))
	var enemy := _add(left + Vector2(30.6, 0.0))
	enemy.move_speed = 0.0
	enemy.prepare(0.2)
	enemy.receive_hit(0.0, enemy.global_position, Vector2.LEFT * 3600.0)
	for _step in 100:
		_lab.advance(TEST_STEP)
		_check(enemy.global_position.x >= left.x + enemy.radius - 0.15,
			"Knockback is constrained by the side wall")
	await _clear()
	var a := _add(left + Vector2(30.6, 0.0))
	var b := _add(left + Vector2(57.0, 0.0))
	a.move_speed = 0.0
	b.move_speed = 0.0
	_lab.advance(0.5)
	_check(a.global_position.x >= left.x + a.radius - 0.15, "Crowd correction cannot push an enemy through a wall")
	_check(a.global_position.distance_to(b.global_position) > 57.0, "Overlapping enemies separate")
	await _clear()


func _test_flippers() -> void:
	for raised: bool in [false, true]:
		_lab.flippers.reset_input()
		if raised:
			_lab.flippers.advance(0.5, true, true)
			_lab.flippers.advance(0.1, true, true)
		for side: int in 2:
			var flipper := _lab.flippers.items[side]
			var tangent := (flipper.tip_position() - flipper.global_position).normalized()
			var normal := Vector2(tangent.y, -tangent.x) * (1.0 if side == 0 else -1.0)
			var middle := flipper.global_position.lerp(flipper.tip_position(), 0.5)
			var enemy := _add(middle + normal * 36.0)
			enemy.move_speed = 0.0
			enemy.prepare(0.2)
			enemy.receive_hit(0.0, middle, -normal * 600.0)
			# Keep this pose stationary while testing its actual collision surface.
			for _step in 40:
				enemy.prepare(TEST_STEP)
				enemy.advance(TEST_STEP)
			_check((enemy.global_position - middle).dot(normal) >= enemy.radius - 0.15,
				"Resting and raised flippers block enemies")
			await _clear()
	_lab.flippers.reset_input()
	var flipper := _lab.flippers.items[0]
	var tangent := (flipper.tip_position() - flipper.global_position).normalized()
	var normal := Vector2(tangent.y, -tangent.x)
	var enemy := _add(flipper.global_position.lerp(flipper.tip_position(), 0.5) + normal * 33.0)
	enemy.move_speed = 0.0
	Input.action_press(&"pinball_left")
	_lab.advance(0.1)
	Input.action_release(&"pinball_left")
	var closest := Geometry2D.get_closest_point_to_segment(enemy.global_position,
		flipper.global_position, flipper.tip_position())
	_check(enemy.global_position.distance_to(closest) >= enemy.radius - 0.2,
		"Moving flipper pushes a stationary enemy clear")
	await _clear()
	_lab.flippers.reset_input()
	var ball_radius := _lab.ball.radius
	var swing := _lab.flippers.swing_angle
	var speed := _lab.flippers.raise_speed
	_lab.ball.radius = 36.0
	_lab.flippers.swing_angle = 60.0
	_lab.flippers.raise_speed = 1440.0
	tangent = (flipper.tip_position() - flipper.global_position).normalized()
	normal = Vector2(tangent.y, -tangent.x)
	enemy = _add(flipper.global_position.lerp(flipper.tip_position(), 0.8) + normal * 6.3)
	enemy.radius = 6.0
	enemy.move_speed = 0.0
	enemy.prepare(0.2)
	Input.action_press(&"pinball_left")
	_lab.advance(0.05)
	Input.action_release(&"pinball_left")
	tangent = (flipper.tip_position() - flipper.global_position).normalized()
	normal = Vector2(tangent.y, -tangent.x)
	closest = Geometry2D.get_closest_point_to_segment(enemy.global_position,
		flipper.global_position, flipper.tip_position())
	_check((enemy.global_position - closest).dot(normal) >= enemy.radius - 0.2,
		"Fast flipper preserves the inside face even for the smallest configured enemy")
	await _clear()
	_lab.ball.radius = ball_radius
	_lab.flippers.swing_angle = swing
	_lab.flippers.raise_speed = speed
	_lab.flippers.reset_input()


func _test_combat() -> void:
	var base_damage := _lab.ball.damage
	_lab.ball.damage = 10.0
	var enemy := _add(Vector2(960.0, 720.0))
	enemy.move_speed = 0.0
	enemy.prepare(0.2)
	var hits := [0]
	enemy.damaged.connect(func(_damage: float, _point: Vector2, _knockback: Vector2) -> void: hits[0] += 1)
	_lab.ball.max_speed = 3600.0
	_lab.place_ball(enemy.global_position + Vector2.UP * (_lab.ball.radius + enemy.radius + 6.0), Vector2.DOWN * 1200.0)
	_lab.ball.advance(0.02)
	_check(absf(_lab.ball.velocity.y + 960.0) < 1.0, "Ball reflects from the enemy")
	_check(absf(enemy.current_health - 88.0) < 0.01, "Damage includes base and ball-speed terms")
	_check(absf(enemy.knockback_velocity().y - 540.0) < 0.01, "Knockback includes base and ball-speed terms")
	for _step in 12:
		_lab.ball.advance(TEST_STEP)
	_check(hits[0] == 1, "A continuous contact does not damage repeatedly")
	enemy.velocity = Vector2.DOWN * 120.0
	_lab.place_ball(enemy.global_position + Vector2.UP * (_lab.ball.radius + enemy.radius + 6.0),
		Vector2.DOWN * 1200.0)
	_lab.ball.advance(0.02)
	_check(absf(_lab.ball.velocity.y + 744.0) < 1.0, "Reflection considers the enemy's actual velocity")
	var sound_count := [0]
	enemy.death_cue = load("res://enemies/death.tres") as SoundCue
	enemy.sound_requested.disconnect(_lab.get_node("WorldSoundOutput").request)
	enemy.sound_requested.connect(func(_request: SoundRequest) -> void: sound_count[0] += 1)
	enemy.receive_hit(1000.0, enemy.global_position, Vector2.DOWN * 300.0)
	_check(not enemy.active and _lab.enemies.is_empty(), "Death removes the enemy once")
	_check(sound_count[0] == 1, "Lethal hit requests the archived death sound")
	enemy.finish(Enemy.ExitReason.ESCAPED)
	_check(sound_count[0] == 1, "Repeated finish cannot repeat death events")
	await _clear()
	var lethal := _add(Vector2(960.0, 720.0))
	lethal.move_speed = 0.0
	lethal.prepare(0.2)
	_lab.ball.damage = 1000.0
	_lab.place_ball(lethal.global_position + Vector2.UP * (_lab.ball.radius + lethal.radius + 6.0),
		Vector2.DOWN * 1200.0)
	_lab.ball.advance(0.02)
	_check(not lethal.active and _lab.ball.velocity.y < -300.0, "A lethal contact still reflects the ball")
	_lab.ball.damage = base_damage
	await _clear()
	_lab.place_ball(Vector2(1800.0, 90.0))


func _test_spawn_clock() -> void:
	_lab.spawner.interval = 0.5
	_lab.spawner.enabled = true
	_lab._physics_process(0.25)
	_check(_lab.enemies.is_empty(), "Spawning waits for the full interval")
	_lab._physics_process(0.25)
	_check(_lab.enemies.size() == 1, "Spawning follows simulation time")
	_lab.spawner.enabled = false
	await _clear()


func _add(point: Vector2) -> Enemy:
	var enemy := ENEMY.instantiate() as Enemy
	enemy.death_cue = null
	enemy.position = point
	_lab.spawner.spawn_parent.add_child(enemy)
	_lab.spawner.enemy_spawned.emit(enemy)
	return enemy


func _clear() -> void:
	for enemy: Enemy in _lab.enemies.duplicate():
		enemy.finish(Enemy.ExitReason.ESCAPED)
	await process_frame


func _sync() -> void:
	await process_frame
	await process_frame
	for _frame in 8:
		await physics_frame


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
