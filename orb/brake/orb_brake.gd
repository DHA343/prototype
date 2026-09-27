class_name OrbBrake
extends Node

signal started
signal ended(duration: float)

enum State {
	RELEASED,
	ACTIVE,
	INTERRUPTED,
}

@export_range(0.1, 30.0, 0.1, "suffix:1/s") var damping: float = 8.0
@export_range(0.0, 1000.0, 1.0, "suffix:px/s") var stop_speed: float = 10.0

var is_active: bool:
	get: return _state == State.ACTIVE

var _movement: OrbMovement
var _active_duration: float = 0.0
var _state: State = State.RELEASED


func setup(movement: OrbMovement) -> void:
	assert(movement != null, "movement must not be null.")
	assert(_movement == null, "OrbBrake must not be setup more than once.")

	_movement = movement


func update(delta: float) -> void:
	assert(_movement != null, "OrbBrake must be setup before updating.")

	if not is_active:
		return

	_active_duration += delta
	_movement.decelerate(delta, damping, stop_speed)


func set_pressed(is_pressed: bool) -> void:
	assert(_movement != null, "OrbBrake must be setup before changing its state.")

	if is_pressed:
		if _state != State.RELEASED:
			return

		_state = State.ACTIVE
		_active_duration = 0.0
		started.emit()
		return

	if _state == State.RELEASED:
		return

	var was_active := _state == State.ACTIVE
	_state = State.RELEASED
	if was_active:
		_end_active_period()


func interrupt_until_released() -> void:
	if _state != State.ACTIVE:
		return

	_state = State.INTERRUPTED
	_end_active_period()


func _end_active_period() -> void:
	ended.emit(_active_duration)
	_active_duration = 0.0
