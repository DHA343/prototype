@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("glitch.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

