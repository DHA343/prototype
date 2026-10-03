@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("painting.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER

