class_name PlayerInput
extends Node

signal boost_requested
signal brake_pressed_changed(is_pressed: bool)

var movement_direction: Vector2:
	get:
		return Input.get_vector("left", "right", "up", "down")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("boost"):
		boost_requested.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("brake"):
		brake_pressed_changed.emit(true)
		get_viewport().set_input_as_handled()
	elif event.is_action_released("brake"):
		brake_pressed_changed.emit(false)
		get_viewport().set_input_as_handled()


func get_aim_offset(origin: Node2D) -> Vector2:
	return origin.get_global_mouse_position() - origin.global_position


func is_action_pressed(action: StringName) -> bool:
	return Input.is_action_pressed(action)


func is_action_just_pressed(action: StringName) -> bool:
	return Input.is_action_just_pressed(action)


func is_action_just_released(action: StringName) -> bool:
	return Input.is_action_just_released(action)
