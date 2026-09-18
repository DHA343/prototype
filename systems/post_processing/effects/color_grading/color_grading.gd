@tool
class_name ColorGrading
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./color_grading.gdshader")

@export_range(-1.0, 1.0, 0.01) var brightness: float = 0.0:
	set(value):
		if is_equal_approx(brightness, value):
			return

		brightness = value
		emit_changed()

@export_range(0.0, 2.0, 0.01) var contrast: float = 1.0:
	set(value):
		if is_equal_approx(contrast, value):
			return

		contrast = value
		emit_changed()

@export_range(0.0, 2.0, 0.01) var saturation: float = 1.0:
	set(value):
		if is_equal_approx(saturation, value):
			return

		saturation = value
		emit_changed()

@export_range(-180.0, 180.0, 1.0, "suffix:deg") var hue: float = 0.0:
	set(value):
		if is_equal_approx(hue, value):
			return

		hue = value
		emit_changed()

@export_range(0.1, 3.0, 0.01) var gamma: float = 1.0:
	set(value):
		if is_equal_approx(gamma, value):
			return

		gamma = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	_shader_parameters[&"brightness"] = brightness
	_shader_parameters[&"contrast"] = contrast
	_shader_parameters[&"saturation"] = saturation
	_shader_parameters[&"hue"] = hue
	_shader_parameters[&"gamma"] = gamma
