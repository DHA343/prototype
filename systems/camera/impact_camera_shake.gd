class_name ImpactCameraShake
extends Node

var _pending_trauma: float = 0.0
var _flush_scheduled: bool = false

@onready var _camera_shake: CameraShake = get_parent() as CameraShake


func _ready() -> void:
	assert(_camera_shake != null, "ImpactCameraShake must be a child of CameraShake.")


func request_trauma(amount: float) -> void:
	if amount <= 0.0:
		return

	_pending_trauma = maxf(_pending_trauma, clampf(amount, 0.0, 1.0))
	if _flush_scheduled:
		return

	_flush_scheduled = true
	call_deferred("_flush_pending_trauma")


func _flush_pending_trauma() -> void:
	_flush_scheduled = false
	if _pending_trauma <= 0.0:
		return

	_camera_shake.add_trauma(_pending_trauma)
	_pending_trauma = 0.0
