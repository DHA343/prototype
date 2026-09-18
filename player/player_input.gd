class_name PlayerInput
extends Node


var movement_direction: Vector2:
	get:
		return Input.get_vector("left", "right", "up", "down")

var is_attack_pressed: bool:
	get:
		return Input.is_action_pressed("attack")


func get_aim_offset(origin: Node2D) -> Vector2:
	return origin.get_global_mouse_position() - origin.global_position
