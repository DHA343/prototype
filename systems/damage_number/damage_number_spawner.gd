class_name DamageNumberSpawner
extends Node2D

@export var damage_number_scene: PackedScene


func _ready() -> void:
	if damage_number_scene == null:
		push_error("damage_number_scene is not assigned.")


func spawn(damage: float, knockback_velocity: Vector2, hit_position: Vector2) -> void:
	if damage_number_scene == null:
		return

	var instance := damage_number_scene.instantiate()
	var damage_number := instance as DamageNumber
	if damage_number == null:
		push_error("damage_number_scene must have a DamageNumber root node.")
		instance.queue_free()
		return

	add_child(damage_number)
	damage_number.global_position = hit_position
	damage_number.launch(damage, knockback_velocity)
