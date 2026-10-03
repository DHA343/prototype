@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("auto_exposure.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER


func needs_history() -> bool:
	return true

