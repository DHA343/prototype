class_name Player
extends CharacterBody2D

signal sound_requested(request: SoundRequest)
signal camera_shake_requested(trauma: float)

@export_group("Movement")
@export_range(0.0, 2000.0, 10.0, "suffix:unit/s") var move_speed: float = 360.0

@export_group("Crowd")
@export var crowd: CrowdSettings

@export_group("Combat")
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.0:
	set(value):
		knockback_resistance = clampf(value, 0.0, 1.0)

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var knockback: Knockback = $Knockback
@onready var player_input: PlayerInput = $PlayerInput
@onready var _ability_controller: AbilityController = $AbilityController
@onready var _attack_root: Node2D = $AttackRoot


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	_ability_controller.sound_requested.connect(_on_sound_requested)
	_ability_controller.camera_shake_requested.connect(_on_camera_shake_requested)
	_ability_controller.setup(self, player_input, _attack_root)


func _physics_process(delta: float) -> void:
	var movement_velocity := player_input.movement_direction * move_speed

	knockback.update(delta)
	velocity = movement_velocity + knockback.velocity
	move_and_slide()


func _on_hurtbox_hit_received(hit: HitData) -> void:
	health.take_damage(hit.damage)

	knockback.apply_hit(hit, knockback_resistance)


func _on_sound_requested(request: SoundRequest) -> void:
	sound_requested.emit(request)


func _on_camera_shake_requested(trauma: float) -> void:
	camera_shake_requested.emit(trauma)
