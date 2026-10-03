@tool
extends ExperimentEffect


func get_shader() -> Shader:
	return preload("tone_mapping.gdshader")
