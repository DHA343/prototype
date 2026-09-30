@tool
class_name CRTBloomSource
extends Node

var _effect: PostProcessEffect
var _main_viewport: Viewport
var _layer_index: int
var _bloom_material: ShaderMaterial
var _source_viewport: SubViewport
var _core_material: ShaderMaterial
var _attached_canvases: Dictionary[RID, bool] = {}


func initialize(
	effect: PostProcessEffect,
	main_viewport: Viewport,
	layer_index: int,
	bloom_material: ShaderMaterial,
) -> void:
	_effect = effect
	_main_viewport = main_viewport
	_layer_index = layer_index
	_bloom_material = bloom_material


func _ready() -> void:
	_source_viewport = SubViewport.new()
	_source_viewport.name = "Emission"
	_source_viewport.size = Vector2i(_main_viewport.get_visible_rect().size)
	_source_viewport.world_2d = _main_viewport.world_2d
	_source_viewport.use_hdr_2d = true
	_source_viewport.disable_3d = true
	_source_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_source_viewport)

	var layer := CanvasLayer.new()
	layer.name = "Core"
	layer.layer = _layer_index
	_source_viewport.add_child(layer)

	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(copy)

	_core_material = ShaderMaterial.new()
	_core_material.shader = _effect.get_shader()
	_effect.apply_to(_core_material)
	_core_material.set_shader_parameter(&"beam_hdr_compression_enabled", false)

	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _core_material
	layer.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_bloom_material.set_shader_parameter(&"phosphor_source_texture", _source_viewport.get_texture())
	_effect.changed.connect(_on_effect_changed, CONNECT_DEFERRED)
	_sync_viewport()
	_update_enabled_state()


func _process(_delta: float) -> void:
	_sync_viewport()
	_update_enabled_state()


func _exit_tree() -> void:
	if is_instance_valid(_effect) and _effect.changed.is_connected(_on_effect_changed):
		_effect.changed.disconnect(_on_effect_changed)

	if is_instance_valid(_source_viewport):
		for canvas in _attached_canvases:
			RenderingServer.viewport_remove_canvas(_source_viewport.get_viewport_rid(), canvas)
	_attached_canvases.clear()


func _on_effect_changed() -> void:
	if not is_instance_valid(_core_material):
		return

	_effect.apply_to(_core_material)
	_core_material.set_shader_parameter(&"beam_hdr_compression_enabled", false)
	_update_enabled_state()


func _sync_viewport() -> void:
	if not is_instance_valid(_main_viewport) or not is_instance_valid(_source_viewport):
		return

	var source_size := Vector2i(_main_viewport.get_visible_rect().size)
	if _source_viewport.size != source_size:
		_source_viewport.size = source_size
	_source_viewport.canvas_transform = _main_viewport.canvas_transform
	_source_viewport.global_canvas_transform = _main_viewport.global_canvas_transform

	var scene_root: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if scene_root == null:
		return

	var current_canvases: Dictionary[RID, bool] = {}
	for node in scene_root.find_children("*", "CanvasLayer", true, false):
		var canvas_layer := node as CanvasLayer
		if canvas_layer.get_viewport() != _main_viewport or canvas_layer.layer >= _layer_index:
			continue
		if canvas_layer.custom_viewport != null and canvas_layer.custom_viewport != _main_viewport:
			continue

		var canvas := canvas_layer.get_canvas()
		if not canvas.is_valid():
			continue
		current_canvases[canvas] = true
		if not _attached_canvases.has(canvas):
			RenderingServer.viewport_attach_canvas(_source_viewport.get_viewport_rid(), canvas)
			_attached_canvases[canvas] = true
		RenderingServer.viewport_set_canvas_stacking(
			_source_viewport.get_viewport_rid(), canvas, canvas_layer.layer, 0
		)
		RenderingServer.viewport_set_canvas_transform(
			_source_viewport.get_viewport_rid(), canvas, canvas_layer.get_final_transform()
		)

	for canvas in _attached_canvases.keys():
		if not current_canvases.has(canvas):
			RenderingServer.viewport_remove_canvas(_source_viewport.get_viewport_rid(), canvas)
			_attached_canvases.erase(canvas)


func _update_enabled_state() -> void:
	if not is_instance_valid(_source_viewport):
		return

	var post_processing := get_parent() as PostProcessing
	var is_enabled := (
		post_processing != null and post_processing.enabled
		and _effect.enabled and _effect.is_pass_enabled(1)
	)
	_source_viewport.render_target_update_mode = (
		SubViewport.UPDATE_ALWAYS if is_enabled else SubViewport.UPDATE_DISABLED
	)
