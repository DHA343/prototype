@tool
class_name DisplayTexture
extends PostProcessEffect

enum MaskStyle {
	STRETCHED_VGA,
	VGA,
}

const EFFECT_SHADER: Shader = preload("./display_texture.gdshader")

@export_group("Scanlines", "scanline_")
@export_range(0.0, 1.0, 0.01) var scanline_strength: float = 0.12:
	set(value):
		if is_equal_approx(scanline_strength, value):
			return

		scanline_strength = value
		emit_changed()

@export_range(2.0, 8.0, 0.1, "suffix:px") var scanline_size: float = 3.0:
	set(value):
		if is_equal_approx(scanline_size, value):
			return

		scanline_size = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var scanline_luminance_influence: float = 0.5:
	set(value):
		if is_equal_approx(scanline_luminance_influence, value):
			return

		scanline_luminance_influence = value
		emit_changed()

@export_group("Shadow Mask", "mask_")
@export var mask_style: MaskStyle = MaskStyle.STRETCHED_VGA:
	set(value):
		if mask_style == value:
			return

		mask_style = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var mask_strength: float = 0.67:
	set(value):
		if is_equal_approx(mask_strength, value):
			return

		mask_strength = value
		emit_changed()

@export_group("Output")
@export_range(0.5, 2.0, 0.01) var brightness_compensation: float = 1.0:
	set(value):
		if is_equal_approx(brightness_compensation, value):
			return

		brightness_compensation = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	_shader_parameters[&"scanline_strength"] = scanline_strength
	_shader_parameters[&"scanline_size"] = scanline_size
	_shader_parameters[&"luminance_influence"] = scanline_luminance_influence
	_shader_parameters[&"mask_style"] = mask_style
	_shader_parameters[&"mask_strength"] = mask_strength
	_shader_parameters[&"brightness_compensation"] = brightness_compensation
