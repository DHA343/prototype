@tool
extends ExperimentEffect

const EFFECT_SHADER: Shader = preload("blur.gdshader")


func get_shader() -> Shader:
	return EFFECT_SHADER


func create_pass_source(_pass_index: int, context: PassSourceContext, material: ShaderMaterial) -> Node:
	if int(get_parameter(&"mode")) != 1:
		return null
	var source := preload("../_shared/pyramid_source.gd").new()
	source.initialize(self, context, material)
	return source

