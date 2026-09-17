@tool
class_name Pixelation
extends PostProcessEffect

const EFFECT_SHADER: Shader = preload("./pixelation.gdshader")

@export_range(1, 32, 1, "suffix:px") var pixel_size: int = 4:
	set(value):
		if pixel_size == value:
			return

		pixel_size = value
		notify_change()

@export var reference_resolution: Vector2 = Vector2(1920.0, 1080.0):
	set(value):
		var safe_resolution := Vector2(maxf(value.x, 1.0), maxf(value.y, 1.0))
		if reference_resolution == safe_resolution:
			return

		reference_resolution = safe_resolution
		notify_change()


func _get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	shader_parameters[&"pixel_size"] = pixel_size
	shader_parameters[&"reference_resolution"] = reference_resolution
