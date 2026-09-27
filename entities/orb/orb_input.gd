class_name OrbInput
extends Node

signal boost_requested
signal brake_pressed_changed(is_pressed: bool)

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
