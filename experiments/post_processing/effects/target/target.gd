@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("target.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

