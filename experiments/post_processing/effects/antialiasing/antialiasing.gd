@tool
extends ExperimentEffect


func get_shader() -> Shader:
	return preload("antialiasing.gdshader")
