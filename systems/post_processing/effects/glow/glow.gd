@tool
class_name Glow
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./glow.gdshader")

@export_range(0.0, 8.0, 0.05) var threshold: float = 1.0:
	set(value):
		if is_equal_approx(threshold, value):
			return

		threshold = value
		notify_change()

@export_range(0.01, 4.0, 0.05) var softness: float = 1.0:
	set(value):
		if is_equal_approx(softness, value):
			return

		softness = value
		notify_change()

@export_range(0.0, 10.0, 0.05) var strength: float = 0.5:
	set(value):
		if is_equal_approx(strength, value):
			return

		strength = value
		notify_change()

@export_range(0.0, 16.0, 0.5, "suffix:px") var radius: float = 4.0:
	set(value):
		if is_equal_approx(radius, value):
			return

		radius = value
		notify_change()


func _get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	shader_parameters[&"threshold"] = threshold
	shader_parameters[&"softness"] = softness
	shader_parameters[&"strength"] = strength
	shader_parameters[&"radius"] = radius
