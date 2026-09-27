class_name GameCamera
extends Camera2D
## Write base_offset for framing; offset is composed with shake each frame.

@export var base_offset: Vector2 = Vector2.ZERO

@onready var _shake: CameraShake = $CameraShake


func _ready() -> void:
	offset = base_offset


func _process(delta: float) -> void:
	offset = base_offset + _shake.update(delta)
