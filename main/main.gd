class_name PinballLab
extends Node2D

signal bumper_hit(center: Vector2)

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
	_advance_enemies(delta, swings)
	if ball.active:
		ball.advance(delta, swings, enemies)
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


## Returns the predicted directed shot velocity in world coordinates, or zero.
func predict_shot() -> Vector2:
	return $Playfield/ShotGuide.predict_shot()


func _advance_enemies(delta: float, _swings: Array[PinballFlipper.Swing]) -> void:
	for enemy: Enemy in enemies:
		enemy.prepare(delta)
	crowd.calculate(enemies, delta, boundary.exit_target())
	for enemy: Enemy in enemies:
		enemy.advance(delta)


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


func _on_bumper_hit(point: Vector2, source: CharacterBody2D, bumper: PinballBumper) -> void:
	if source == ball or source == null:
		bumper_hit.emit(bumper.global_position)
	if bumper.hit_sound != null:
		_sound.request(SoundRequest.new(bumper.hit_sound, point, bumper))

