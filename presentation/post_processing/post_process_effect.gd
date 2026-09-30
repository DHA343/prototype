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


func get_pass_count() -> int:
	return 1


func get_pass_shader(_pass_index: int) -> Shader:
	return get_shader()


func apply_to(material: ShaderMaterial) -> void:
	_shader_parameters.clear()
	_update_shader_parameters()
	for parameter_name in _shader_parameters:
		material.set_shader_parameter(parameter_name, _shader_parameters[parameter_name])


func apply_to_pass(material: ShaderMaterial, _pass_index: int) -> void:
	apply_to(material)


func is_pass_enabled(_pass_index: int) -> bool:
	return true


func create_pass_source(
	_pass_index: int,
	_main_viewport: Viewport,
	_layer_index: int,
	_material: ShaderMaterial,
) -> Node:
	return null


@abstract
func _update_shader_parameters() -> void
