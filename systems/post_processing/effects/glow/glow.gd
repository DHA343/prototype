@tool
class_name Glow
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./glow.gdshader")

@export_range(0.0, 8.0, 0.1) var threshold: float = 1.0:
	set(value):
		if is_equal_approx(threshold, value):
			return

		threshold = value
		emit_changed()

@export_range(0.01, 4.0, 0.1) var softness: float = 1.0:
	set(value):
		if is_equal_approx(softness, value):
			return

		softness = value
		emit_changed()

@export_range(0.0, 10.0, 0.1) var strength: float = 0.5:
	set(value):
		if is_equal_approx(strength, value):
			return

		strength = value
		emit_changed()

@export_range(0.0, 16.0, 0.1, "suffix:px") var radius: float = 4.0:
	set(value):
		if is_equal_approx(radius, value):
			return

		radius = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	_shader_parameters[&"threshold"] = threshold
	_shader_parameters[&"softness"] = softness
	_shader_parameters[&"strength"] = strength
	_shader_parameters[&"radius"] = radius
