class_name OrbMovement
extends Node

@export_range(100.0, 10000.0, 100.0, "suffix:px/s") var target_speed: float = 6000.0
@export_range(100.0, 20000.0, 100.0, "suffix:px/s²") var acceleration: float = 10000.0
@export_range(100.0, 20000.0, 100.0, "suffix:px/s") var max_speed: float = 7000.0

var velocity: Vector2:
	get: return _velocity

var heading: Vector2:
	get: return _heading

var _velocity: Vector2 = Vector2.ZERO
var _heading: Vector2 = Vector2.RIGHT


func update(delta: float, global_position: Vector2, target_position: Vector2) -> void:
	var to_target := target_position - global_position
	if to_target.is_zero_approx():
		_set_velocity(_velocity.move_toward(Vector2.ZERO, acceleration * delta))
		return

	var desired_velocity := to_target.normalized() * target_speed
	_set_velocity(
		_velocity.move_toward(desired_velocity, acceleration * delta).limit_length(max_speed)
	)


func clear() -> void:
	_set_velocity(Vector2.ZERO)


func add_velocity(delta_velocity: Vector2) -> void:
	_set_velocity((_velocity + delta_velocity).limit_length(max_speed))


func decelerate(delta: float, damping: float, stop_speed: float) -> void:
	assert(delta >= 0.0, "delta must not be negative.")
	assert(damping >= 0.0, "damping must not be negative.")
	assert(stop_speed >= 0.0, "stop_speed must not be negative.")

	var next_velocity := _velocity * exp(-damping * delta)
	if next_velocity.length() <= stop_speed:
		next_velocity = Vector2.ZERO

	_set_velocity(next_velocity)


func _set_velocity(value: Vector2) -> void:
	_velocity = value
	if not value.is_zero_approx():
		_heading = value.normalized()
