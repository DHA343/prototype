class_name PhysicsPositionInterpolator
extends RefCounted

var _previous_physics_position: Vector2 = Vector2.ZERO
var _current_physics_position: Vector2 = Vector2.ZERO


func reset(position: Vector2) -> void:
	_previous_physics_position = position
	_current_physics_position = position


func record_position(position: Vector2) -> void:
	_previous_physics_position = _current_physics_position
	_current_physics_position = position


func get_interpolated_global_position() -> Vector2:
	var interpolation_fraction := Engine.get_physics_interpolation_fraction()
	return _previous_physics_position.lerp(_current_physics_position, interpolation_fraction)
