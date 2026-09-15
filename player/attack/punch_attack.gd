class_name PunchAttack
extends Node2D

@export_group("Hit")
@export_range(0.0, 1000.0, 0.1) var damage: float = 10.0
@export_range(0.0, 2000.0, 10.0, "suffix:unit/s") var knockback: float = 300.0
@export_range(0.01, 1.0, 0.01, "suffix:s") var hit_active_duration: float = 0.09

@export_group("Audio")
@export var hit_sound: SoundCue

@export_group("Layout")
@export_range(0.0, 100.0, 1.0, "suffix:unit") var side_offset: float = 14.0
@export_range(0.0, 150.0, 1.0, "suffix:unit") var hitbox_forward_offset: float = 46.0

@export_group("Visual")
@export_range(0.0, 150.0, 1.0, "suffix:unit") var visual_start_distance: float = 30.0
@export_range(0.0, 150.0, 1.0, "suffix:unit") var visual_end_distance: float = 56.0
@export_range(0.01, 1.0, 0.01, "suffix:s") var move_duration: float = 0.10
@export_range(0.0, 1.0, 0.01, "suffix:s") var fade_start: float = 0.09
@export_range(0.01, 1.0, 0.01, "suffix:s") var fade_duration: float = 0.05
@export_range(0.01, 1.0, 0.01, "suffix:s") var lifetime: float = 0.14

var _attacker: Node = null
var _world_sound_output: WorldSoundOutput
var _direction: Vector2 = Vector2.RIGHT
var _side_sign: float = -1.0
var _hit_hurtbox_ids: Dictionary = {}

@onready var _visual_root: Node2D = $VisualRoot
@onready var _hitbox: Hitbox = $Hitbox
@onready var _collision_shape: CollisionShape2D = $Hitbox/CollisionShape2D


func _ready() -> void:
	global_rotation = _direction.angle()
	_collision_shape.position = Vector2(hitbox_forward_offset, side_offset * _side_sign)
	_collision_shape.rotation = PI * 0.5
	_hitbox.hurtbox_detected.connect(_on_hurtbox_detected)
	_hitbox.monitoring = true

	_play_visual()
	get_tree().create_timer(hit_active_duration).timeout.connect(_disable_hitbox)
	get_tree().create_timer(lifetime).timeout.connect(queue_free)


func setup(
	attacker: Node,
	direction: Vector2,
	side_sign: float,
	world_sound_output: WorldSoundOutput
) -> void:
	_attacker = attacker
	_world_sound_output = world_sound_output
	_direction = direction.normalized()
	if _direction.is_zero_approx():
		_direction = Vector2.RIGHT
	_side_sign = -1.0 if side_sign < 0.0 else 1.0


func _on_hurtbox_detected(hurtbox: Hurtbox) -> void:
	var hurtbox_id := hurtbox.get_instance_id()
	if _hit_hurtbox_ids.has(hurtbox_id):
		return

	_hit_hurtbox_ids[hurtbox_id] = true
	var hit := HitData.new()
	hit.attacker = _attacker
	hit.damage = damage
	hit.knockback = knockback
	hit.hit_position = hurtbox.global_position
	hit.hit_direction = _direction
	hurtbox.receive_hit(hit)
	_play_hit_sound(hit.hit_position)


func _play_hit_sound(hit_position: Vector2) -> void:
	if hit_sound == null:
		return
	if not is_instance_valid(_world_sound_output):
		push_error("world_sound_output is not assigned.")
		return

	var sound_request := SoundRequest.new(hit_sound, hit_position, self)
	_world_sound_output.request(sound_request)


func _play_visual() -> void:
	var start_position := Vector2(visual_start_distance, side_offset * _side_sign)
	var end_position := Vector2(visual_end_distance, side_offset * _side_sign)
	_visual_root.position = start_position

	var move_tween := create_tween()
	move_tween.tween_property(
		_visual_root,
		"position",
		end_position,
		move_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var fade_tween := create_tween()
	fade_tween.tween_interval(fade_start)
	fade_tween.tween_property(_visual_root, "modulate:a", 0.0, fade_duration)


func _disable_hitbox() -> void:
	_hitbox.monitoring = false
