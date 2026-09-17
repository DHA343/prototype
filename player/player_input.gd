class_name PlayerInput
extends Node


var movement_direction: Vector2:
	get:
		return Input.get_vector("left", "right", "up", "down")
