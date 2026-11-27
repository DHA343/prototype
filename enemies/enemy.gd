@tool
class_name Enemy
extends CharacterBody2D

signal removed(enemy: Enemy, reason: ExitReason)
signal damaged(amount: float, point: Vector2, knockback_velocity: Vector2)
signal sound_requested(request: SoundRequest)

enum ExitReason { KILLED, ESCAPED }

const MAX_CONTACTS: int = 8

@export_group("Body")
@export_range(6.0, 72.0, 1.5, "suffix:px") var radius: float = 30.0:
	set(value):
		radius = value
		_refresh_shape()
@export_range(0.0, 1.0, 0.01) var restitution: float = 0.8

@export_group("Movement")
@export_range(0.0, 600.0, 15.0, "suffix:px/s") var move_speed: float = 120.0
@export_range(0.0, 3000.0, 30.0, "suffix:px/s²") var acceleration: float = 540.0
@export_range(0.1, 2.0, 0.1, "suffix:s") var repath_interval: float = 0.5

@export_group("Combat")
@export_range(1.0, 1000.0, 1.0) var max_health: float = 100.0
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.0
@export_range(0.0, 15000.0, 30.0, "suffix:px/s") var max_knockback: float = 3600.0
@export_range(0.01, 2.0, 0.01, "suffix:s") var knockback_duration: float = 0.24

@export_group("Presentation")
@export var full_health_color: Color = Color(0.2, 0.7, 1.0)
@export var low_health_color: Color = Color(1.0, 0.3, 0.3)
@export var death_cue: SoundCue
@export_range(0.01, 1.0, 0.01, "suffix:s") var grow_duration: float = 0.12
@export_range(1.0, 2.0, 0.05) var spawn_peak: float = 1.3
@export_range(0.0, 1.0, 0.05) var hit_scale_pull: float = 0.25
@export_range(10.0, 500.0, 10.0) var spring_stiffness: float = 200.0
@export_range(0.0, 40.0, 1.0) var spring_damping: float = 10.0

var active: bool = true
var current_health: float = 100.0
var crowd_motion: Vector2 = Vector2.ZERO
var _routes: EnemyRoutes
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _path_revision: int = -1
var _repath_remaining: float = 0.0
var _movement_velocity: Vector2 = Vector2.ZERO
var _knockback_initial: Vector2 = Vector2.ZERO
var _knockback_elapsed: float = 0.0
var _spawn_elapsed: float = 0.0
var _visual_scale: float = 1.0
var _spring_velocity: float = 0.0

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	collision_layer = 0 if not Engine.is_editor_hint() else 4
	collision_mask = 2
	current_health = max_health
	_visual_scale = 1.0 if Engine.is_editor_hint() else 0.1
	_refresh_shape()


func _draw() -> void:
	var ratio := clampf(current_health / max_health, 0.0, 1.0)
	draw_circle(Vector2.ZERO, radius * _visual_scale, low_health_color.lerp(full_health_color, ratio))


func start(routes: EnemyRoutes) -> void:
	_routes = routes
	_repath_remaining = 0.0


func prepare(delta: float) -> void:
	if not active:
		return
	_advance_presentation(delta)
	var desired := _route_velocity(delta)
	_movement_velocity = _movement_velocity.move_toward(desired, acceleration * delta)


func advance(delta: float) -> void:
	if not active:
		return
	var before := global_position
	var motion := (_movement_velocity + knockback_velocity()) * delta + crowd_motion
	for _contact in MAX_CONTACTS:
		var collision := move_and_collide(motion, false, 0.03, true)
		if collision == null:
			break
		var normal := collision.get_normal()
		motion = collision.get_remainder().slide(normal)
		if _movement_velocity.dot(normal) < 0.0:
			_movement_velocity = _movement_velocity.slide(normal)
		if _knockback_initial.dot(normal) < 0.0:
			_knockback_initial = _knockback_initial.slide(normal)
		if motion.length_squared() < 0.000001:
			break
	velocity = (global_position - before) / delta
	_knockback_elapsed += delta
	if _knockback_elapsed >= knockback_duration:
		_knockback_initial = Vector2.ZERO
	crowd_motion = Vector2.ZERO


func knockback_velocity() -> Vector2:
	var ratio := 1.0 - clampf(_knockback_elapsed / knockback_duration, 0.0, 1.0)
	return _knockback_initial * ratio * ratio


func receive_ball_hit(amount: float, point: Vector2, impulse: Vector2) -> void:
	receive_hit(amount, point, impulse)


func receive_hit(amount: float, point: Vector2, impulse: Vector2) -> bool:
	if not active or _spawn_elapsed < grow_duration:
		return false
	current_health = maxf(0.0, current_health - maxf(amount, 0.0))
	var impulse_velocity := impulse * (1.0 - knockback_resistance)
	_knockback_initial = (knockback_velocity() + impulse_velocity).limit_length(max_knockback)
	_knockback_elapsed = 0.0
	_spawn_elapsed = grow_duration
	_visual_scale = 1.0 + hit_scale_pull
	_spring_velocity = 0.0
	queue_redraw()
	damaged.emit(amount, point, _knockback_initial)
	if current_health <= 0.0:
		if death_cue != null:
			sound_requested.emit(SoundRequest.new(death_cue, global_position, self))
		finish(ExitReason.KILLED)
	return true


func finish(reason: ExitReason) -> void:
	if not active:
		return
	active = false
	collision_layer = 0
	visible = false
	removed.emit(self, reason)
	queue_free()


func _route_velocity(delta: float) -> Vector2:
	_repath_remaining -= delta
	if _routes != null and (_repath_remaining <= 0.0 or _path_revision != _routes.revision):
		_path = _routes.path_from(global_position, radius)
		_path_index = 0
		_path_revision = _routes.revision
		_repath_remaining = repath_interval
	while _path_index < _path.size() and global_position.distance_to(_path[_path_index]) < 3.0:
		_path_index += 1
	if _path_index < _path.size():
		return global_position.direction_to(_path[_path_index]) * move_speed
	return Vector2.ZERO


func _advance_presentation(delta: float) -> void:
	var was_growing := _spawn_elapsed < grow_duration
	_spawn_elapsed += delta
	if was_growing:
		var ratio := clampf(_spawn_elapsed / grow_duration, 0.0, 1.0)
		_visual_scale = lerpf(0.1, spawn_peak, 1.0 - (1.0 - ratio) * (1.0 - ratio))
		if _spawn_elapsed >= grow_duration:
			collision_layer = 4
	else:
		_spring_velocity += (-spring_stiffness * (_visual_scale - 1.0)
			- spring_damping * _spring_velocity) * delta
		_spring_velocity = clampf(_spring_velocity, -10.0, 10.0)
		_visual_scale += _spring_velocity * delta
	queue_redraw()


func _refresh_shape() -> void:
	queue_redraw()
	if is_node_ready():
		var circle := CircleShape2D.new()
		circle.radius = radius
		_collision.shape = circle
