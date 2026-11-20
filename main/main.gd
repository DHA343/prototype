class_name PinballLab
extends Node2D

signal bumper_hit(center: Vector2)

const PREDICTION_STEP: float = 1.0 / 240.0

@export_range(0.0, 1.0, 0.05, "suffix:s") var respawn_delay: float = 0.45

var enemies: Array[Enemy] = []
var _spawn_position: Vector2
var _respawn_remaining: float = 0.0

@onready var ball: PinballBall = $Playfield/Ball
@onready var flippers: PinballFlippers = $Playfield/Flippers
@onready var boundary: PinballBoundary = $Playfield/Boundary
@onready var spawner: EnemySpawner = $EnemySpawner
@onready var routes: EnemyRoutes = $Routes
@onready var crowd: CrowdManager = $CrowdManager
@onready var launcher := get_node_or_null("Playfield/MissileLauncher") as MissileLauncher
@onready var _sound: WorldSoundOutput = $WorldSoundOutput


func _ready() -> void:
	ball.boundary = boundary
	ball.flippers = flippers
	ball.sound_requested.connect(_sound.request)
	_spawn_position = ball.global_position
	var bumpers: Array[PinballBumper] = []
	for child: Node in $Playfield.find_children("*", "", true, false):
		var bumper := child as PinballBumper
		if bumper != null:
			bumpers.append(bumper)
			bumper.hit_occurred.connect(_on_bumper_hit.bind(bumper))
	routes.setup(boundary, bumpers)
	spawner.setup(_can_spawn_enemy)
	routes.prepare(spawner.enemy_radius)
	spawner.enemy_spawned.connect(_on_enemy_spawned)
	reset_ball()


func _physics_process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if delta <= 0:
		return
	routes.refresh()
	var left_pressed := Input.is_action_pressed(&"pinball_left")
	var right_pressed := Input.is_action_pressed(&"pinball_right")
	var swings := flippers.plan_motion(left_pressed, right_pressed)
	flippers.advance(delta, left_pressed, right_pressed)
	for enemy: Enemy in enemies:
		enemy.prepare(delta)
	crowd.calculate(enemies, delta, boundary.exit_target())
	for enemy: Enemy in enemies:
		enemy.advance(delta)
	if ball.active:
		ball.advance(delta, swings)
		if boundary.to_local(ball.global_position).y > boundary.bottom + 120.0:
			ball.active = false
			ball.visible = false
			_respawn_remaining = respawn_delay
	else:
		_respawn_remaining -= delta
		if _respawn_remaining <= 0:
			reset_ball()
	# Resolve exits after all motion, so removal never mutates the movement iteration.
	for index in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[index]
		if boundary.has_exited(enemy.global_position, enemy.radius):
			enemy.finish(Enemy.ExitReason.ESCAPED)
	spawner.advance(delta)
	if is_instance_valid(launcher):
		launcher.advance(delta, enemies)


func place_ball(point: Vector2, initial_velocity: Vector2 = Vector2.ZERO) -> void:
	ball.reset_at(point, initial_velocity)
	_respawn_remaining = 0.0


func reset_ball() -> void:
	flippers.reset_input()
	place_ball(_spawn_position)


## Returns the predicted shot velocity in world coordinates, or zero when no shot is predicted.
func predict_shot() -> Vector2:
	if not ball.active or flippers.is_target_disabled(ball.get_instance_id()):
		return Vector2.ZERO
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = (ball.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.collision_mask = ball.collision_mask
	var excluded: Array[RID] = [ball.get_rid()]
	for flipper: PinballFlipper in flippers.items:
		excluded.append(flipper.get_rid())
	query.exclude = excluded
	var space := ball.get_world_2d().direct_space_state
	var position := ball.global_position
	var velocity := ball.velocity
	var elapsed := 0.0
	var swings := flippers.plan_motion(true, true)
	var stationary := flippers.items.duplicate()
	for swing: PinballFlipper.Swing in swings:
		stationary.erase(swing.flipper)
	var horizon := deg_to_rad(flippers.swing_angle) / deg_to_rad(flippers.raise_speed)
	var step_limit := flippers.motion_step_limit(ball.radius, true, true)
	while elapsed < horizon:
		var step := minf(minf(PREDICTION_STEP, step_limit), horizon - elapsed)
		velocity = ball.step_velocity(velocity, step)
		query.transform = Transform2D(0.0, position)
		query.motion = velocity * step
		var travel := space.cast_motion(query)
		var hit := flippers.first_contact(swings, position, velocity, ball.radius, elapsed, step * travel[0])
		if not hit.is_empty() and (travel[0] >= 1.0 or hit.time < step * travel[0]):
			var normal: Vector2 = hit.normal
			var surface_velocity: Vector2 = hit.surface_velocity
			if (velocity - surface_velocity).dot(normal) < 0.0:
				var reflected := PinballBall.reflected_velocity(velocity, normal,
					flippers.restitution, hit.strike_surface_velocity)
				if hit.is_striking:
					var flipper: PinballFlipper = hit.flipper
					reflected = flippers.direct_shot(reflected, hit.ratio, flipper.side, normal)
				return reflected.limit_length(ball.max_speed)
		# A wall or bumper reached first invalidates this direct flipper preview.
		if travel[0] < 1.0:
			return Vector2.ZERO
		position += query.motion
		elapsed += step
		for flipper: PinballFlipper in stationary:
			if not flipper.visible:
				continue
			var contact := flipper.predicted_contact(position, ball.radius, elapsed, step,
				flippers.swing_angle, flippers.raise_speed, flippers.power_equalization)
			if contact.is_empty():
				continue
			var normal: Vector2 = contact["normal"]
			var surface_velocity: Vector2 = contact["surface_velocity"]
			if (velocity - surface_velocity).dot(normal) < 0.0:
				surface_velocity = contact["strike_surface_velocity"]
				var reflected := PinballBall.reflected_velocity(velocity, normal,
					flippers.restitution, surface_velocity)
				if contact["is_striking"]:
					reflected = flippers.direct_shot(reflected, contact["ratio"], flipper.side, normal)
				return reflected.limit_length(ball.max_speed)
	return Vector2.ZERO


func _can_spawn_enemy(point: Vector2, radius: float) -> bool:
	if not routes.is_spawn_point(point, radius):
		return false
	var shape := CircleShape2D.new()
	shape.radius = radius + 1.5
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, point)
	query.collision_mask = 7
	if not ball.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	# Growing enemies reserve space before their ball collision becomes active.
	for enemy: Enemy in enemies:
		if point.distance_to(enemy.global_position) < radius + enemy.radius + 1.5:
			return false
	return true


func _on_enemy_spawned(enemy: Enemy) -> void:
	enemies.append(enemy)
	enemy.removed.connect(_on_enemy_removed)
	enemy.sound_requested.connect(_sound.request)
	enemy.start(routes)


func _on_enemy_removed(enemy: Enemy, _reason: Enemy.ExitReason) -> void:
	enemies.erase(enemy)


func _on_bumper_hit(point: Vector2, bumper: PinballBumper) -> void:
	bumper_hit.emit(bumper.global_position)
	if bumper.hit_sound != null:
		_sound.request(SoundRequest.new(bumper.hit_sound, point, bumper))

