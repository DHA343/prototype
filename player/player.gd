class_name Player
extends CharacterBody2D

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


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)


func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector("left", "right", "up", "down")
	var movement_velocity := input_direction * move_speed

	knockback.update(delta)
	velocity = movement_velocity + knockback.velocity
	move_and_slide()


func _on_hurtbox_hit_received(hit: HitData) -> void:
	health.take_damage(hit.damage)

	var direction := hit.hit_direction.normalized()
	var multiplier := 1.0 - knockback_resistance
	var knockback_velocity := direction * hit.knockback * multiplier
	knockback.apply(knockback_velocity)
