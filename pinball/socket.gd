@tool
class_name PinballSocket
extends Marker2D

signal changed

var available: bool = false:
	set(value):
		if available == value:
			return
		available = value
		changed.emit()


func _ready() -> void:
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		changed.emit()
