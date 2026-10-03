@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("motion_blur.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

