@tool
@abstract
class_name PostProcessEffect
extends Resource

@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return

		enabled = value
		notify_change()

var shader_parameters: Dictionary[StringName, Variant] = {}


@abstract
func _get_shader() -> Shader


@abstract
func _update_shader_parameters() -> void


func is_enabled() -> bool:
	return enabled


func notify_change() -> void:
	emit_changed()
