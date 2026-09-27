@tool
class_name Blur
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./blur.gdshader")

@export_range(0.0, 16.0, 0.1, "suffix:px") var radius: float = 4.0:
	set(value):
		if is_equal_approx(radius, value):
			return

		radius = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var strength: float = 1.0:
	set(value):
		if is_equal_approx(strength, value):
			return

		strength = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	_shader_parameters[&"radius"] = radius
	_shader_parameters[&"strength"] = strength
