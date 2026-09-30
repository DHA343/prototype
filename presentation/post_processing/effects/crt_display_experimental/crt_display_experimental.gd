@tool
class_name CRTDisplayExperimental
extends PostProcessEffect

enum MaskStyle {
	STRETCHED_VGA,
	VGA,
	DOTS,
	APERTURE_GRILLE,
	WIDE_GRILLE,
	WIDE_SOFT_GRILLE,
	SLOT_MASK,
}

const EFFECT_SHADER: Shader = preload("./crt_display_experimental.gdshader")

@export_group("Scanline")
@export var signal_enabled: bool = true:
	set(value):
		if signal_enabled == value:
			return

		signal_enabled = value
		emit_changed()

@export_range(180, 720, 1, "suffix:lines") var scanline_count: int = 360:
	set(value):
		if scanline_count == value:
			return

		scanline_count = value
		emit_changed()

@export_group("Signal Reconstruction")
@export_range(0.5, 1.0, 0.01) var sharpness: float = 0.67:
	set(value):
		if is_equal_approx(sharpness, value):
			return

		sharpness = value
		emit_changed()

@export_range(0.5, 3.0, 0.1, "suffix:px") var signal_pitch: float = 1.5:
	set(value):
		if is_equal_approx(signal_pitch, value):
			return

		signal_pitch = value
		emit_changed()

@export_group("Beam", "beam_")
@export_range(0.2, 0.55, 0.01) var beam_min_width: float = 0.34:
	set(value):
		if is_equal_approx(beam_min_width, value):
			return

		beam_min_width = value
		emit_changed()

@export_range(0.2, 0.55, 0.01) var beam_max_width: float = 0.42:
	set(value):
		if is_equal_approx(beam_max_width, value):
			return

		beam_max_width = value
		emit_changed()

@export_range(0.0, 2.0, 0.01) var beam_bloom_strength: float = 0.25:
	set(value):
		if is_equal_approx(beam_bloom_strength, value):
			return

		beam_bloom_strength = value
		emit_changed()

@export_range(0.0, 0.25, 0.01) var beam_bloom_limit: float = 0.12:
	set(value):
		if is_equal_approx(beam_bloom_limit, value):
			return

		beam_bloom_limit = value
		emit_changed()

@export_group("Shadow Mask", "mask_")
@export var mask_style: MaskStyle = MaskStyle.STRETCHED_VGA:
	set(value):
		if mask_style == value:
			return

		mask_style = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var mask_strength: float = 0.5:
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
	_shader_parameters[&"signal_enabled"] = signal_enabled
	_shader_parameters[&"scanline_count"] = scanline_count
	_shader_parameters[&"sharpness"] = sharpness
	_shader_parameters[&"signal_pitch"] = signal_pitch
	_shader_parameters[&"beam_min_width"] = beam_min_width
	_shader_parameters[&"beam_max_width"] = beam_max_width
	_shader_parameters[&"beam_bloom_strength"] = beam_bloom_strength
	_shader_parameters[&"beam_bloom_limit"] = beam_bloom_limit
	_shader_parameters[&"mask_style"] = mask_style
	_shader_parameters[&"mask_strength"] = mask_strength
	_shader_parameters[&"brightness_compensation"] = brightness_compensation
