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
const BLOOM_SHADER: Shader = preload("./crt_display_experimental_bloom.gdshader")

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
@export_range(0.2, 0.55, 0.01) var beam_width: float = 0.42:
	set(value):
		if is_equal_approx(beam_width, value):
			return

		beam_width = value
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

@export_group("Phosphor Bloom", "phosphor_bloom_")
@export var phosphor_bloom_enabled: bool = true:
	set(value):
		if phosphor_bloom_enabled == value:
			return

		phosphor_bloom_enabled = value
		emit_changed()

@export_range(0.0, 12.0, 0.1, "suffix:px") var phosphor_bloom_radius: float = 5.0:
	set(value):
		if is_equal_approx(phosphor_bloom_radius, value):
			return

		phosphor_bloom_radius = value
		emit_changed()

@export_range(0.0, 1.0, 0.01) var phosphor_bloom_strength: float = 0.2:
	set(value):
		if is_equal_approx(phosphor_bloom_strength, value):
			return

		phosphor_bloom_strength = value
		emit_changed()

@export_range(9, 17, 2) var phosphor_bloom_taps: int = 13:
	set(value):
		if phosphor_bloom_taps == value:
			return

		phosphor_bloom_taps = value
		emit_changed()


func get_shader() -> Shader:
	return EFFECT_SHADER


func get_pass_count() -> int:
	return 2


func get_pass_shader(pass_index: int) -> Shader:
	return EFFECT_SHADER if pass_index == 0 else BLOOM_SHADER


func apply_to_pass(material: ShaderMaterial, pass_index: int) -> void:
	if pass_index == 0:
		apply_to(material)
		return

	material.set_shader_parameter(&"phosphor_bloom_radius", phosphor_bloom_radius)
	material.set_shader_parameter(&"phosphor_bloom_strength", phosphor_bloom_strength)
	material.set_shader_parameter(&"phosphor_bloom_taps", phosphor_bloom_taps)


func is_pass_enabled(pass_index: int) -> bool:
	return pass_index == 0 or (
		phosphor_bloom_enabled and phosphor_bloom_strength > 0.0 and phosphor_bloom_radius > 0.0
	)


func _update_shader_parameters() -> void:
	_shader_parameters[&"signal_enabled"] = signal_enabled
	_shader_parameters[&"scanline_count"] = scanline_count
	_shader_parameters[&"sharpness"] = sharpness
	_shader_parameters[&"signal_pitch"] = signal_pitch
	_shader_parameters[&"beam_width"] = beam_width
	_shader_parameters[&"mask_style"] = mask_style
	_shader_parameters[&"mask_strength"] = mask_strength
	_shader_parameters[&"brightness_compensation"] = brightness_compensation
