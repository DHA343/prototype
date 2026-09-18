@tool
class_name ShadowMask
extends PostProcessEffect

enum MaskStyle {
	STRETCHED_VGA,
	VGA,
}

const EFFECT_SHADER: Shader = preload("./shadow_mask.gdshader")

@export var mask_style: MaskStyle = MaskStyle.STRETCHED_VGA:
	set(value):
		if mask_style == value:
			return

		mask_style = value
		emit_changed()

@export var bgr_subpixels: bool = false:
	set(value):
		if bgr_subpixels == value:
			return

		bgr_subpixels = value
		emit_changed()

@export_range(0.0, 2.0, 0.1) var mask_dark: float = 0.5:
	set(value):
		if is_equal_approx(mask_dark, value):
			return

		mask_dark = value
		emit_changed()

@export_range(0.0, 2.0, 0.1) var mask_light: float = 1.5:
	set(value):
		if is_equal_approx(mask_light, value):
			return

		mask_light = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	_shader_parameters[&"mask_style"] = mask_style
	_shader_parameters[&"bgr_subpixels"] = bgr_subpixels
	_shader_parameters[&"mask_dark"] = mask_dark
	_shader_parameters[&"mask_light"] = mask_light
