@tool
extends ExperimentEffect


func get_shader() -> Shader:
	return preload("pseudo_3d.gdshader")
