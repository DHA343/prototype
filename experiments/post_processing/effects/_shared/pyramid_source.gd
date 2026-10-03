@tool
extends "history_source.gd"

const FILTER: Shader = preload("pyramid_filter.gdshader")

var _pyramid: Array[SubViewport] = []
var _filters: Array[ShaderMaterial] = []
var _divisors: Array[int] = []


func _ready() -> void:
	super._ready()
	RenderingServer.frame_post_draw.disconnect(_capture)
	var source := _viewport
	var bloom: bool = _effect.get_shader().resource_path.get_file() == "lens.gdshader"
	if bloom:
		source = _filter(source, 2, 1)
	var down: Array[SubViewport] = [source]
	for level in range(1, 5):
		source = _filter(source, 0, 1 << level)
		down.append(source)
	for level in range(3, -1, -1):
		source = _filter(source, 1, 1 << level)
		_filters.back().set_shader_parameter(&"detail_texture", down[level].get_texture())
		_filters.back().set_shader_parameter(&"bloom", bloom)
	_effect.set_runtime_parameter(&"pyramid_texture", source.get_texture())
	_process(0.0)


func _process(delta: float) -> void:
	super._process(delta)
	for index in _pyramid.size():
		_pyramid[index].size = (_viewport.size / _divisors[index]).max(Vector2i.ONE)
		_pyramid[index].render_target_update_mode = _viewport.render_target_update_mode
		_filters[index].set_shader_parameter(&"radius", float(_effect.get_parameter(&"radius")) / 8.0)
		var threshold: Variant = _effect.get_parameter(&"threshold")
		if threshold != null:
			_filters[index].set_shader_parameter(&"threshold", threshold)


func _filter(input: SubViewport, stage: int, divisor: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.disable_3d = true
	viewport.use_hdr_2d = true
	viewport.size = (_viewport.size / divisor).max(Vector2i.ONE)
	add_child(viewport)
	_pyramid.append(viewport)
	_divisors.append(divisor)
	var material := ShaderMaterial.new()
	material.shader = FILTER
	material.set_shader_parameter(&"input_texture", input.get_texture())
	material.set_shader_parameter(&"stage", stage)
	_filters.append(material)
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	viewport.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return viewport
