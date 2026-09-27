@tool
class_name CheckerboardBackground
extends ColorRect

@export var dark_color: Color = Color(0.05, 0.055, 0.07, 1.0):
	set(value):
		dark_color = value
		_set_shader_parameter(&"dark_color", value)
@export var light_color: Color = Color(0.075, 0.08, 0.1, 1.0):
	set(value):
		light_color = value
		_set_shader_parameter(&"light_color", value)
@export_range(1.0, 512.0, 1.0, "suffix:px") var cell_size: float = 96.0:
	set(value):
		cell_size = maxf(value, 1.0)
		_set_shader_parameter(&"cell_size", cell_size)
@export_range(1.0, 4.0, 0.1) var coverage_multiplier: float = 2.0:
	set(value):
		coverage_multiplier = maxf(value, 1.0)
		_update_coverage()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_shader_parameters()
	_update_coverage()

	if not get_viewport().size_changed.is_connected(_update_coverage):
		get_viewport().size_changed.connect(_update_coverage)


func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_update_coverage):
		get_viewport().size_changed.disconnect(_update_coverage)


func _update_coverage() -> void:
	if not is_inside_tree():
		return

	var coverage_size := get_viewport_rect().size * coverage_multiplier
	position = -coverage_size * 0.5
	size = coverage_size


func _update_shader_parameters() -> void:
	_set_shader_parameter(&"dark_color", dark_color)
	_set_shader_parameter(&"light_color", light_color)
	_set_shader_parameter(&"cell_size", cell_size)


func _set_shader_parameter(parameter: StringName, value: Variant) -> void:
	var shader_material := material as ShaderMaterial
	if shader_material == null:
		return

	shader_material.set_shader_parameter(parameter, value)
