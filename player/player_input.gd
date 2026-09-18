class_name PlayerInput
extends Node


var movement_direction: Vector2:
	get:
		return Input.get_vector("left", "right", "up", "down")

func get_aim_offset(origin: Node2D) -> Vector2:
	return origin.get_global_mouse_position() - origin.global_position


func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)


func is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)


func is_action_just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)
