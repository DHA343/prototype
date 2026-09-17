@tool
class_name Vignette
extends PostProcessEffect

enum ShapeMode {
	SCREEN_ELLIPSE,
	PHYSICAL_CIRCLE,
}

const EFFECT_SHADER: Shader = preload("./vignette.gdshader")

@export_range(0.0, 1.0, 0.01) var strength: float = 0.18:
	set(value):
		if is_equal_approx(strength, value):
			return

		strength = value
		notify_change()

@export_range(0.0, 1.0, 0.01) var radius: float = 0.58:
	set(value):
		if is_equal_approx(radius, value):
			return

		radius = value
		notify_change()

@export_range(0.0, 1.0, 0.01) var softness: float = 0.35:
	set(value):
		if is_equal_approx(softness, value):
			return

		softness = value
		notify_change()

@export_range(0.1, 4.0, 0.01) var falloff: float = 1.8:
	set(value):
		if is_equal_approx(falloff, value):
			return

		falloff = value
		notify_change()

@export var shape_mode: ShapeMode = ShapeMode.SCREEN_ELLIPSE:
	set(value):
		if shape_mode == value:
			return

		shape_mode = value
		notify_change()

@export_range(0.25, 0.75, 0.01) var center_x: float = 0.5:
	set(value):
		if is_equal_approx(center_x, value):
			return

		center_x = value
		notify_change()

@export_range(0.25, 0.75, 0.01) var center_y: float = 0.48:
	set(value):
		if is_equal_approx(center_y, value):
			return

		center_y = value
		notify_change()

@export var vignette_color: Color = Color(0.008, 0.004, 0.02, 1.0):
	set(value):
		if vignette_color == value:
			return

		vignette_color = value
		notify_change()


func _get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	shader_parameters[&"strength"] = strength
	shader_parameters[&"radius"] = radius
	shader_parameters[&"softness"] = softness
	shader_parameters[&"falloff"] = falloff
	shader_parameters[&"shape_mode"] = shape_mode
	shader_parameters[&"center_x"] = center_x
	shader_parameters[&"center_y"] = center_y
	shader_parameters[&"vignette_color"] = vignette_color
