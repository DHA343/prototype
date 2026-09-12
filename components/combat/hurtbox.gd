class_name Hurtbox
extends Area2D

signal hit_received(hit: HitData)

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D


func receive_hit(hit: HitData) -> void:
	hit_received.emit(hit)


func set_enabled(value: bool) -> void:
	_collision_shape.set_deferred("disabled", not value)
