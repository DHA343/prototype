@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("dithering.gdshader")
const BLUE_NOISE: Texture2D = preload("blue_noise.png")


func get_shader() -> Shader:
	return EFFECT_SHADER


func get_parameter(parameter: StringName) -> Variant:
	if parameter == &"blue_noise" and not parameters.has(parameter):
		return BLUE_NOISE
	return super.get_parameter(parameter)

