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
const BLOOM_SHADER: Shader = preload("./phosphor_bloom.gdshader")

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
## Full width at half maximum, relative to the scanline spacing.
@export_range(0.5, 1.25, 0.01, "suffix:lines") var beam_width: float = 0.94:
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

@export_range(0.5, 8.0, 0.1, "suffix:px @1080p") var phosphor_bloom_near_width: float = 2.0:
	set(value):
		if is_equal_approx(phosphor_bloom_near_width, value):
			return

		phosphor_bloom_near_width = value
		emit_changed()

@export_range(4.0, 64.0, 0.5, "suffix:px @1080p") var phosphor_bloom_far_width: float = 16.0:
	set(value):
		if is_equal_approx(phosphor_bloom_far_width, value):
			return

		phosphor_bloom_far_width = value
		emit_changed()

@export_range(0.0, 0.25, 0.005) var phosphor_bloom_near_strength: float = 0.06:
	set(value):
		if is_equal_approx(phosphor_bloom_near_strength, value):
			return

		phosphor_bloom_near_strength = value
		emit_changed()

@export_range(0.0, 0.1, 0.001) var phosphor_bloom_far_strength: float = 0.01:
	set(value):
		if is_equal_approx(phosphor_bloom_far_strength, value):
			return

		phosphor_bloom_far_strength = value
		emit_changed()

## Limits Bloom source intensity, without compressing the Core output.
@export_range(1.0, 16.0, 0.1) var phosphor_bloom_hdr_limit: float = 2.0:
	set(value):
		if is_equal_approx(phosphor_bloom_hdr_limit, value):
			return

		phosphor_bloom_hdr_limit = value
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

	material.set_shader_parameter(&"bloom_hdr_limit", phosphor_bloom_hdr_limit)
	material.set_shader_parameter(&"near_strength", phosphor_bloom_near_strength)
	material.set_shader_parameter(&"far_strength", phosphor_bloom_far_strength)


func is_pass_enabled(pass_index: int) -> bool:
	return pass_index == 0 or (
		phosphor_bloom_enabled
		and (phosphor_bloom_near_strength > 0.0 or phosphor_bloom_far_strength > 0.0)
	)


func create_pass_source(
	pass_index: int,
	context: PassSourceContext,
	material: ShaderMaterial,
) -> Node:
	if pass_index != 1:
		return null

	var bloom := CRTPhosphorBloom.new()
	bloom.initialize(self, context, material)
	return bloom


func _update_shader_parameters() -> void:
	_shader_parameters[&"signal_enabled"] = signal_enabled
	_shader_parameters[&"scanline_count"] = scanline_count
	_shader_parameters[&"sharpness"] = sharpness
	_shader_parameters[&"signal_pitch"] = signal_pitch
	_shader_parameters[&"beam_width"] = beam_width
	_shader_parameters[&"mask_style"] = mask_style
	_shader_parameters[&"mask_strength"] = mask_strength
	_shader_parameters[&"brightness_compensation"] = brightness_compensation
