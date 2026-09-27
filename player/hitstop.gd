class_name Hitstop
extends Node

enum State {
	IDLE,
	ACTIVE,
	COOLDOWN,
}

@export_range(1, 10, 1) var active_frames: int = 1
@export_range(0, 10, 1) var cooldown_frames: int = 1

var is_stopped: bool:
	get: return _state == State.ACTIVE

var _state: State = State.IDLE
var _remaining_frames: int = 0


func update() -> void:
	_advance_state()

	if _remaining_frames > 0:
		_remaining_frames -= 1


func _advance_state() -> void:
	if _remaining_frames > 0:
		return

	match _state:
		State.ACTIVE:
			_state = State.COOLDOWN if cooldown_frames > 0 else State.IDLE
			_remaining_frames = cooldown_frames
		State.COOLDOWN:
			_state = State.IDLE


func request() -> void:
	if _state != State.IDLE:
		return

	_state = State.ACTIVE
	_remaining_frames = active_frames


func cancel() -> void:
	_state = State.IDLE
	_remaining_frames = 0
