@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("print.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

