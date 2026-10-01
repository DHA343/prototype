@tool
class_name CRTDisplayExperimental
extends PostProcessEffect

enum MaskModel {
	REDISTRIBUTION,
	CELL_EMISSION,
}

enum MaskPattern {
	STAGGERED_RGB = 0,
	STAGGERED_RGB_ROW_PAIRS = 1,
	RGB_PIXEL_PATTERN = 2,
	GREEN_MAGENTA_STRIPES = 3,
}

enum CellSampling {
	HORIZONTAL_4 = 1,
	AREA_2X2 = 2,
}

enum GapAlignment {
	PIXEL_BOUNDARY,
	PIXEL_CENTER,
}

const EFFECT_SHADER: Shader = preload("./crt_display_experimental.gdshader")
const CELL_SHADER: Shader = preload("./phosphor_cells.gdshader")
const SPREAD_SHADER: Shader = preload("./optical_spread.gdshader")
const BLOOM_SHADER: Shader = preload("./phosphor_bloom.gdshader")
const NOISE_SHADER: Shader = preload("./crt_noise.gdshader")

@export_group("Signal Reconstruction")
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

## Average each signal sample's source-pixel area before reconstruction.
## Disable to compare with the previous point-sampled signal.
@export var signal_prefilter_enabled: bool = true:
	set(value):
		if signal_prefilter_enabled == value:
			return

		signal_prefilter_enabled = value
		emit_changed()

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

## Blend horizontal-only signal with the vertically reconstructed signal.
## Zero keeps vertical detail; one applies the full row reconstruction.
@export_range(0.0, 1.0, 0.01) var vertical_blur: float = 1.0:
	set(value):
		if is_equal_approx(vertical_blur, value):
			return

		vertical_blur = value
		emit_changed()

@export_group("Scanline")
## Row brightness modulation, independent of signal reconstruction. Zero disables it.
@export_range(0.0, 1.0, 0.01) var scanline_strength: float = 0.15:
	set(value):
		if is_equal_approx(scanline_strength, value):
			return

		scanline_strength = value
		emit_changed()

## Full width at half maximum of the row light profile, relative to row spacing.
## Changes the scanline pattern without changing vertical reconstruction.
@export_range(0.75, 1.25, 0.01, "suffix:lines") var beam_width: float = 0.9:
	set(value):
		if is_equal_approx(beam_width, value):
			return

		beam_width = value
		emit_changed()

@export_group("Mask")
## Cell Emission supports both staggered RGB layouts.
@export_enum("Mask Redistribution:0", "Cell Emission:1")
var mask_model: int = MaskModel.REDISTRIBUTION:
	set(value):
		if mask_model == value:
			return

		mask_model = value
		if mask_model == MaskModel.CELL_EMISSION and not _is_rgb_layout():
			mask_pattern = MaskPattern.STAGGERED_RGB
		notify_property_list_changed()
		emit_changed()

@export_enum(
	"Staggered RGB:0", "Staggered RGB (Row Pairs):1",
	"RGB Pixel Pattern:2", "Green / Magenta Stripes:3",
)
var mask_pattern: int = MaskPattern.STAGGERED_RGB:
	set(value):
		if value not in MaskPattern.values():
			return
		if mask_model == MaskModel.CELL_EMISSION and value not in [
			MaskPattern.STAGGERED_RGB, MaskPattern.STAGGERED_RGB_ROW_PAIRS,
		]:
			return
		if mask_pattern == value:
			return

		mask_pattern = value
		notify_property_list_changed()
		emit_changed()

## Blend the mask output with the reconstructed signal. Zero removes the mask.
@export_range(0.0, 1.0, 0.01) var mask_strength: float = 0.5:
	set(value):
		if is_equal_approx(mask_strength, value):
			return

		mask_strength = value
		emit_changed()

## RGB triad width in output pixels.
@export_range(2, 6, 1, "suffix:px") var triad_pitch: int = 3:
	set(value):
		if triad_pitch == value:
			return

		triad_pitch = value
		emit_changed()

## Height of one cell row in output pixels.
@export_range(1, 4, 1, "suffix:px") var row_pitch: int = 3:
	set(value):
		if row_pitch == value:
			return

		row_pitch = value
		emit_changed()

## Horizontal modes keep the input's vertical center. 2x2 samples both axes.
@export_enum("Horizontal 4:1", "2x2:2")
var cell_sampling: int = CellSampling.HORIZONTAL_4:
	set(value):
		if value not in CellSampling.values():
			return
		if cell_sampling == value:
			return

		cell_sampling = value
		emit_changed()

## Total non-emitting width per triad, split equally between both ends.
@export_range(0.0, 1.0, 0.05, "suffix:px") var horizontal_gap: float = 0.0:
	set(value):
		if is_equal_approx(horizontal_gap, value):
			return

		horizontal_gap = value
		emit_changed()

## Pixel Center shifts the complete triad, including its gaps, by half a pixel.
@export var gap_alignment: GapAlignment = GapAlignment.PIXEL_BOUNDARY:
	set(value):
		if gap_alignment == value:
			return

		gap_alignment = value
		emit_changed()

## Total non-emitting height per row, split equally between both ends.
@export_range(0.0, 1.0, 0.05, "suffix:px") var vertical_gap: float = 0.0:
	set(value):
		if is_equal_approx(vertical_gap, value):
			return

		vertical_gap = value
		emit_changed()

## Common gain after mask blending. One means no additional compensation.
@export_range(0.25, 6.0, 0.01) var brightness_compensation: float = 1.0:
	set(value):
		if is_equal_approx(brightness_compensation, value):
			return

		brightness_compensation = value
		emit_changed()


@export_group("Optical Spread", "optical_spread_")
## Redistribute Mask light to adjacent pixels. Zero disables the pass.
@export_range(0.0, 1.0, 0.01) var optical_spread_strength: float = 0.5:
	set(value):
		if is_equal_approx(optical_spread_strength, value):
			return

		optical_spread_strength = value
		emit_changed()

## Width of the four-sample footprint in output pixels. Zero disables the pass.
@export_range(0.0, 1.0, 0.05, "suffix:px") var optical_spread_width: float = 0.75:
	set(value):
		if is_equal_approx(optical_spread_width, value):
			return

		optical_spread_width = value
		emit_changed()

@export_group("Phosphor Bloom", "phosphor_bloom_")
@export var phosphor_bloom_enabled: bool = true:
	set(value):
		if phosphor_bloom_enabled == value:
			return

		phosphor_bloom_enabled = value
		emit_changed()

@export_range(0.5, 8.0, 0.1, "suffix:px @1080p") var phosphor_bloom_near_width: float = 4.0:
	set(value):
		if is_equal_approx(phosphor_bloom_near_width, value):
			return

		phosphor_bloom_near_width = value
		emit_changed()

@export_range(4.0, 64.0, 0.1, "suffix:px @1080p") var phosphor_bloom_far_width: float = 32.0:
	set(value):
		if is_equal_approx(phosphor_bloom_far_width, value):
			return

		phosphor_bloom_far_width = value
		emit_changed()

@export_range(0.0, 0.25, 0.01) var phosphor_bloom_near_strength: float = 0.1:
	set(value):
		if is_equal_approx(phosphor_bloom_near_strength, value):
			return

		phosphor_bloom_near_strength = value
		emit_changed()

@export_range(0.0, 0.1, 0.001) var phosphor_bloom_far_strength: float = 0.05:
	set(value):
		if is_equal_approx(phosphor_bloom_far_strength, value):
			return

		phosphor_bloom_far_strength = value
		emit_changed()

## Limits Bloom source intensity, without compressing the Core output.
@export_range(1.0, 32.0, 0.1) var phosphor_bloom_hdr_limit: float = 16.0:
	set(value):
		if is_equal_approx(phosphor_bloom_hdr_limit, value):
			return

		phosphor_bloom_hdr_limit = value
		emit_changed()


@export_group("Noise", "noise_")
@export var noise_enabled: bool = true:
	set(value):
		if noise_enabled == value:
			return

		noise_enabled = value
		emit_changed()

## Brightness grain after Mask and Bloom. Zero disables this component.
@export_range(0.0, 0.25, 0.001) var noise_luma_strength: float = 0.08:
	set(value):
		if is_equal_approx(noise_luma_strength, value):
			return

		noise_luma_strength = value
		emit_changed()

## Perceptual red/green and blue/yellow grain after Bloom. Zero disables it.
@export_range(0.0, 0.1, 0.001) var noise_chroma_strength: float = 0.006:
	set(value):
		if is_equal_approx(noise_chroma_strength, value):
			return

		noise_chroma_strength = value
		emit_changed()

## Grain spacing in output pixels, independent of the mask's cell layout.
@export_range(1.0, 8.0, 0.1, "suffix:px") var noise_size: float = 1.5:
	set(value):
		if is_equal_approx(noise_size, value):
			return

		noise_size = value
		emit_changed()

## Blend hard grain cells with smooth interpolation. Most visible for larger grains.
@export_range(0.0, 1.0, 0.01) var noise_softness: float = 0.6:
	set(value):
		if is_equal_approx(noise_softness, value):
			return

		noise_softness = value
		emit_changed()

## New random pattern per update. Zero keeps the grain still.
@export_range(0.0, 60.0, 1.0, "suffix:Hz") var noise_rate: float = 30.0:
	set(value):
		if is_equal_approx(noise_rate, value):
			return

		noise_rate = value
		emit_changed()


func _validate_property(property: Dictionary) -> void:
	if property.name == "mask_pattern" and _is_cell_emission():
		property.hint_string = "Staggered RGB:0,Staggered RGB (Row Pairs):1"
	elif (
		property.name in ["triad_pitch", "row_pitch"]
		and not _is_rgb_layout()
	):
		property.usage |= PROPERTY_USAGE_READ_ONLY
	elif property.name in [
		"cell_sampling", "horizontal_gap", "gap_alignment", "vertical_gap",
	] and not _is_cell_emission():
		property.usage |= PROPERTY_USAGE_READ_ONLY


func get_shader() -> Shader:
	return EFFECT_SHADER


func get_pass_count() -> int:
	return 5


func get_pass_shader(pass_index: int) -> Shader:
	if pass_index == 0:
		return EFFECT_SHADER
	if pass_index == 1:
		return CELL_SHADER
	if pass_index == 2:
		return SPREAD_SHADER
	return BLOOM_SHADER if pass_index == 3 else NOISE_SHADER


func apply_to_pass(material: ShaderMaterial, pass_index: int) -> void:
	if pass_index == 0:
		apply_to(material)
		return

	if pass_index == 1:
		material.set_shader_parameter(&"cell_sampling", cell_sampling)
		material.set_shader_parameter(&"triad_pitch", float(triad_pitch))
		material.set_shader_parameter(&"row_pitch", row_pitch)
		material.set_shader_parameter(&"mask_pattern", mask_pattern)
		material.set_shader_parameter(&"horizontal_gap", horizontal_gap)
		material.set_shader_parameter(&"gap_alignment", gap_alignment)
		material.set_shader_parameter(&"vertical_gap", vertical_gap)
		material.set_shader_parameter(&"mask_strength", mask_strength)
		material.set_shader_parameter(&"brightness_compensation", brightness_compensation)
		return

	if pass_index == 2:
		material.set_shader_parameter(&"spread_strength", optical_spread_strength)
		material.set_shader_parameter(&"spread_width", optical_spread_width)
		return

	if pass_index == 3:
		material.set_shader_parameter(&"bloom_hdr_limit", phosphor_bloom_hdr_limit)
		material.set_shader_parameter(&"near_strength", phosphor_bloom_near_strength)
		material.set_shader_parameter(&"far_strength", phosphor_bloom_far_strength)
		return

	material.set_shader_parameter(&"luma_strength", noise_luma_strength)
	material.set_shader_parameter(&"chroma_strength", noise_chroma_strength)
	material.set_shader_parameter(&"grain_size", noise_size)
	material.set_shader_parameter(&"grain_softness", noise_softness)
	material.set_shader_parameter(&"refresh_rate", noise_rate)


func is_pass_enabled(pass_index: int) -> bool:
	if pass_index == 0:
		return true
	if pass_index == 1:
		return _is_cell_emission()
	if pass_index == 2:
		return optical_spread_strength > 0.0 and optical_spread_width > 0.0
	if pass_index == 3:
		return (
			phosphor_bloom_enabled
			and (phosphor_bloom_near_strength > 0.0 or phosphor_bloom_far_strength > 0.0)
		)
	return noise_enabled and (noise_luma_strength > 0.0 or noise_chroma_strength > 0.0)


func create_pass_source(
	pass_index: int,
	context: PassSourceContext,
	material: ShaderMaterial,
) -> Node:
	if pass_index != 3:
		return null

	var bloom := CRTPhosphorBloom.new()
	bloom.initialize(self, context, material, pass_index)
	return bloom


func _update_shader_parameters() -> void:
	_shader_parameters[&"signal_enabled"] = signal_enabled
	_shader_parameters[&"signal_prefilter_enabled"] = signal_prefilter_enabled
	_shader_parameters[&"scanline_count"] = scanline_count
	_shader_parameters[&"sharpness"] = sharpness
	_shader_parameters[&"signal_pitch"] = signal_pitch
	_shader_parameters[&"vertical_blur"] = vertical_blur
	_shader_parameters[&"scanline_strength"] = scanline_strength
	_shader_parameters[&"beam_width"] = beam_width
	_shader_parameters[&"mask_model"] = mask_model
	_shader_parameters[&"mask_pattern"] = mask_pattern
	_shader_parameters[&"triad_pitch"] = float(triad_pitch)
	_shader_parameters[&"row_pitch"] = row_pitch
	_shader_parameters[&"mask_strength"] = mask_strength
	_shader_parameters[&"brightness_compensation"] = brightness_compensation


func _is_cell_emission() -> bool:
	return mask_model == MaskModel.CELL_EMISSION


func _is_rgb_layout() -> bool:
	return mask_pattern in [MaskPattern.STAGGERED_RGB, MaskPattern.STAGGERED_RGB_ROW_PAIRS]
