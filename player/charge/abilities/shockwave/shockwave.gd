class_name Shockwave
extends Node2D

signal sound_requested(request: SoundRequest)

@export_group("Shockwave")
@export_range(0.0, 1000.0, 1.0, "suffix:px") var min_radius: float = 100.0
@export_range(0.0, 1000.0, 1.0, "suffix:px") var max_radius: float = 400.0
@export_range(0.01, 2.0, 0.01, "suffix:s") var expand_time: float = 0.2
@export var transition_type: Tween.TransitionType = Tween.TRANS_QUAD
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

@export_group("Hit")
@export_range(0.0, 1000.0, 0.1) var min_damage: float = 10.0
@export_range(0.0, 1000.0, 0.1) var max_damage: float = 60.0
@export_range(0.0, 5000.0, 10.0, "suffix:px/s") var min_impulse_strength: float = 300.0
@export_range(0.0, 5000.0, 10.0, "suffix:px/s") var max_impulse_strength: float = 1500.0

@export_group("Audio")
@export var start_cue: SoundCue
@export var hit_cue: SoundCue

var _shape: CircleShape2D = CircleShape2D.new()
var _charge_level: float = 0.0
var _damage: float = 0.0
var _impulse_strength: float = 0.0

var radius: float = 0.0:
	set(value):
		radius = maxf(value, 0.0)
		_shape.radius = maxf(radius, 0.01)

var visual_radius: float = 0.0:
	set(value):
		visual_radius = maxf(value, 0.0)
		visual.set_radius(visual_radius)

@onready var visual: ShockwaveVisual = $ShockwaveVisual
@onready var hitbox: Hitbox = $Hitbox
@onready var collision: CollisionShape2D = $Hitbox/CollisionShape2D


func _ready() -> void:
	var target_radius := lerpf(min_radius, max_radius, _charge_level)
	_damage = lerpf(min_damage, max_damage, _charge_level)
	_impulse_strength = lerpf(min_impulse_strength, max_impulse_strength, _charge_level)

	if start_cue != null:
		sound_requested.emit(SoundRequest.new(start_cue, global_position, self))

	hitbox.hurtbox_detected.connect(_on_hurtbox_detected)

	collision.shape = _shape
	radius = 0.0
	visual_radius = 0.0

	var physics_tween := create_tween()
	physics_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	physics_tween.tween_property(self, "radius", target_radius, expand_time) \
		.set_trans(transition_type).set_ease(ease_type)
	physics_tween.tween_callback(queue_free)

	var visual_tween := create_tween()
	visual_tween.tween_property(self, "visual_radius", target_radius, expand_time) \
		.set_trans(transition_type).set_ease(ease_type)


func set_charge_level(level: float) -> void:
	_charge_level = clampf(level, 0.0, 1.0)


func _on_hurtbox_detected(hurtbox: Hurtbox) -> void:
	var hit_direction := global_position.direction_to(hurtbox.global_position)
	if hit_direction.is_zero_approx():
		hit_direction = Vector2.RIGHT
	var hit := HitData.new()
	hit.attacker = self
	hit.damage = _damage
	hit.knockback = _impulse_strength
	hit.hit_direction = hit_direction
	hit.hit_position = hurtbox.global_position
	hurtbox.receive_hit(hit)
	if hit_cue != null:
		sound_requested.emit(SoundRequest.new(hit_cue, hurtbox.global_position, self))
