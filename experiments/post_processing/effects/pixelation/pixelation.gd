@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("pixelation.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

