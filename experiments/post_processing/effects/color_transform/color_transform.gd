@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("color_transform.gdshader")
const FILM_LUT: Texture2D = preload("film_lut.png")


func get_shader() -> Shader:
	return EFFECT_SHADER


func get_parameter(parameter: StringName) -> Variant:
	if parameter == &"lut_texture" and not parameters.has(parameter):
		return FILM_LUT
	return super.get_parameter(parameter)

