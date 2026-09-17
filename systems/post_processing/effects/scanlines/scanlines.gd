@tool
class_name Scanlines
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./scanlines.gdshader")

@export_range(1.0, 1080.0, 1.0) var line_count: float = 240.0:
	set(value):
		if is_equal_approx(line_count, value):
			return

		line_count = value
		notify_change()

@export_range(0.01, 1.0, 0.01) var line_thickness: float = 0.5:
	set(value):
		if is_equal_approx(line_thickness, value):
			return

		line_thickness = value
		notify_change()

@export_range(0.0, 0.5, 0.01) var edge_softness: float = 0.05:
	set(value):
		if is_equal_approx(edge_softness, value):
			return

		edge_softness = value
		notify_change()

@export_range(0.0, 1.0, 0.01) var strength: float = 0.3:
	set(value):
		if is_equal_approx(strength, value):
			return

		strength = value
		notify_change()


func _get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	shader_parameters[&"line_count"] = line_count
	shader_parameters[&"line_thickness"] = line_thickness
	shader_parameters[&"edge_softness"] = edge_softness
	shader_parameters[&"strength"] = strength
