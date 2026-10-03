@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("color_grading.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

