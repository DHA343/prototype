@tool
@abstract
class_name PostProcessEffect
extends Resource

@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return

		enabled = value
		emit_changed()

var _shader_parameters: Dictionary[StringName, Variant] = {}


@abstract
func get_shader() -> Shader


func apply_to(material: ShaderMaterial) -> void:
	_shader_parameters.clear()
	_update_shader_parameters()
	for parameter_name in _shader_parameters:
		material.set_shader_parameter(parameter_name, _shader_parameters[parameter_name])


@abstract
func _update_shader_parameters() -> void
