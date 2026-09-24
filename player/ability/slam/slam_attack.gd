class_name SlamAttack
extends Node2D

@export_group("Audio")
@export var slam_sound: SoundCue
@export var hit_sound: SoundCue

@export_group("Visual")
@export var fill_color: Color = Color(0.85, 0.95, 1.0, 0.18)
@export var outline_color: Color = Color(0.95, 1.0, 1.0, 0.9)
@export_range(0.5, 12.0, 0.5, "suffix:unit") var outline_width: float = 4.0

var _attacker: Node
var _feedback: Feedback
var _direction: Vector2 = Vector2.RIGHT
var _target_radius: float = 0.0
var _damage: float = 0.0
var _knockback: float = 0.0
var _expand_duration: float = 0.2
var _elapsed: float = 0.0
var _radius: float = 0.0
var _finished: bool = false
var _hit_hurtbox_ids: Dictionary[int, bool] = {}
var _last_hit_sound_usec: int = -1000000

@onready var _hitbox: Hitbox = $Hitbox
@onready var _collision_shape: CollisionShape2D = $Hitbox/CollisionShape2D


func _ready() -> void:
	_hitbox.monitoring = false
	_collision_shape.shape = CircleShape2D.new()
	_hitbox.hurtbox_detected.connect(_on_hurtbox_detected)
	set_physics_process(false)


func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius, fill_color)
	draw_arc(Vector2.ZERO, _radius, 0.0, TAU, 64, outline_color, outline_width, true)


func _physics_process(delta: float) -> void:
	if _finished:
		queue_free()
		return
	_elapsed = minf(_elapsed + maxf(delta, 0.0), _expand_duration)
	var progress := _elapsed / _expand_duration
	var eased_progress := 1.0 - pow(1.0 - progress, 2.0)
	_radius = maxf(_target_radius * eased_progress, 0.01)
	var circle := _collision_shape.shape as CircleShape2D
	circle.radius = _radius
	queue_redraw()
	if _elapsed >= _expand_duration:
		_finished = true


func launch(
	attacker: Node,
	direction: Vector2,
	radius: float,
	damage: float,
	knockback: float,
	expand_duration: float,
	feedback: Feedback
) -> void:
	_attacker = attacker
	_direction = direction
	_target_radius = maxf(radius, 0.01)
	_damage = damage
	_knockback = knockback
	_expand_duration = maxf(expand_duration, 0.01)
	_feedback = feedback
	_radius = 0.01
	var circle := _collision_shape.shape as CircleShape2D
	circle.radius = _radius
	_hitbox.monitoring = true
	set_physics_process(true)
	if slam_sound != null:
		_feedback.sound_requested.emit(SoundRequest.new(slam_sound, global_position, self))


func _on_hurtbox_detected(hurtbox: Hurtbox) -> void:
	var hurtbox_id := hurtbox.get_instance_id()
	if _hit_hurtbox_ids.has(hurtbox_id):
		return
	_hit_hurtbox_ids[hurtbox_id] = true
	var hit := HitData.new()
	hit.attacker = _attacker
	hit.damage = _damage
	hit.knockback = _knockback
	hit.hit_position = hurtbox.global_position
	hit.hit_direction = (hit.hit_position - global_position).normalized()
	if hit.hit_direction.is_zero_approx():
		hit.hit_direction = _direction
	hurtbox.receive_hit(hit)
	_request_hit_sound(hit.hit_position)


func _request_hit_sound(hit_position: Vector2) -> void:
	if hit_sound == null:
		return
	var now_usec := Time.get_ticks_usec()
	if now_usec - _last_hit_sound_usec < 50000:
		return
	_last_hit_sound_usec = now_usec
	_feedback.sound_requested.emit(SoundRequest.new(hit_sound, hit_position, self))
