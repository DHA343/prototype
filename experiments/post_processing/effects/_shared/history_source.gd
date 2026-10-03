@tool
extends Node

var _effect: ExperimentEffect
var _context: PassSourceContext
var _material: ShaderMaterial
var _viewport: SubViewport
var _history: ImageTexture
var _passes: Dictionary[PassSourceContext.Pass, ColorRect] = {}
var _copies: Dictionary[PassSourceContext.Pass, BackBufferCopy] = {}
var _canvases: Dictionary[RID, WeakRef] = {}
var _feedback: ColorRect
var _elapsed: float = 0.0
var _exposure: float = 1.0
var _was_enabled: bool = false


func initialize(effect: ExperimentEffect, context: PassSourceContext, material: ShaderMaterial) -> void:
	_effect = effect
	_context = context
	_material = material


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "HistoryInput"
	_viewport.disable_3d = true
	_viewport.use_hdr_2d = true
	_viewport.world_2d = _context.main_viewport.world_2d
	add_child(_viewport)
	var layer := CanvasLayer.new()
	layer.layer = _context.layer_index
	_viewport.add_child(layer)
	for preceding in _context.preceding_passes:
		var copy := BackBufferCopy.new()
		copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
		layer.add_child(copy)
		_copies[preceding] = copy
		var rect := ColorRect.new()
		rect.material = preceding.material
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(rect)
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_passes[preceding] = rect
	var feedback_copy := BackBufferCopy.new()
	feedback_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	layer.add_child(feedback_copy)
	_feedback = ColorRect.new()
	_feedback.material = _material
	_feedback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_feedback)
	_feedback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync()
	RenderingServer.frame_post_draw.connect(_capture)


func _process(delta: float) -> void:
	_effect.set_runtime_parameter(&"frame_delta", minf(delta, 0.1))
	_elapsed += delta
	_sync()


func _exit_tree() -> void:
	if RenderingServer.frame_post_draw.is_connected(_capture):
		RenderingServer.frame_post_draw.disconnect(_capture)
	for canvas: RID in _canvases:
		if _canvases[canvas].get_ref() != null:
			RenderingServer.viewport_remove_canvas(_viewport.get_viewport_rid(), canvas)


func _sync() -> void:
	var main := _context.main_viewport
	var size := Vector2i(main.get_visible_rect().size)
	if _viewport.size != size:
		_viewport.size = size.max(Vector2i.ONE)
		_history = null
		_effect.reset_history()
	_viewport.canvas_transform = main.canvas_transform
	_viewport.global_canvas_transform = main.global_canvas_transform
	_viewport.snap_2d_transforms_to_pixel = main.snap_2d_transforms_to_pixel
	_viewport.canvas_item_default_texture_filter = main.canvas_item_default_texture_filter
	_viewport.transparent_bg = main.transparent_bg
	var enabled_now := _context.is_enabled()
	if enabled_now != _was_enabled:
		_effect.reset_history()
		_was_enabled = enabled_now
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled_now else SubViewport.UPDATE_DISABLED
	for preceding in _passes:
		_passes[preceding].visible = preceding.is_enabled()
		_copies[preceding].visible = preceding.is_enabled()
	var filename := _effect.get_shader().resource_path.get_file()
	var mode: int = int(_effect.get_parameter(&"mode")) if filename == "temporal.gdshader" else -1
	_feedback.visible = mode in [0, 2, 3, 4, 6]
	var scene: Node = get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
	if scene == null:
		return
	var current: Dictionary[RID, bool] = {}
	for node in scene.find_children("*", "CanvasLayer", true, false):
		var layer := node as CanvasLayer
		if layer.get_viewport() != main or layer.layer >= _context.layer_index:
			continue
		if layer.custom_viewport != null and layer.custom_viewport != main:
			continue
		var canvas := layer.get_canvas()
		current[canvas] = true
		if not _canvases.has(canvas):
			RenderingServer.viewport_attach_canvas(_viewport.get_viewport_rid(), canvas)
			_canvases[canvas] = weakref(layer)
		RenderingServer.viewport_set_canvas_stacking(_viewport.get_viewport_rid(), canvas, layer.layer, 0)
		RenderingServer.viewport_set_canvas_transform(_viewport.get_viewport_rid(), canvas, layer.get_final_transform())
	for canvas: RID in _canvases.keys():
		if not current.has(canvas):
			if _canvases[canvas].get_ref() != null:
				RenderingServer.viewport_remove_canvas(_viewport.get_viewport_rid(), canvas)
			_canvases.erase(canvas)


func _capture() -> void:
	if not is_inside_tree() or not _context.is_enabled() or DisplayServer.get_name() == "headless":
		return
	var filename := _effect.get_shader().resource_path.get_file()
	if filename == "temporal.gdshader" and int(_effect.get_parameter(&"mode")) == 5:
		var interval := 1.0 / maxf(float(_effect.get_parameter(&"capture_fps")), 1.0)
		if _history != null and bool(_effect.get_runtime_parameter(&"history_valid")) and _elapsed < interval:
			return
	var image := _viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return
	if filename == "auto_exposure.gdshader":
		image.resize(32, 32, Image.INTERPOLATE_BILINEAR)
		var sum_log: float = 0.0
		for y in 32:
			for x in 32:
				var c := image.get_pixel(x, y)
				sum_log += log(maxf(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722, 0.0001))
		var mean := exp(sum_log / 1024.0)
		var desired := clampf(float(_effect.get_parameter(&"middle_gray")) / mean,
			float(_effect.get_parameter(&"min_exposure")), float(_effect.get_parameter(&"max_exposure")))
		_exposure = lerpf(_exposure, desired, 1.0 - exp(-_elapsed * float(_effect.get_parameter(&"adaptation_speed"))))
		_effect.set_runtime_parameter(&"adapted_exposure", _exposure)
	else:
		if _history == null or _history.get_width() != image.get_width() or _history.get_height() != image.get_height():
			_history = ImageTexture.create_from_image(image)
		else:
			_history.update(image)
		_effect.set_runtime_parameter(&"history_texture", _history)
		_effect.set_runtime_parameter(&"history_valid", true)
	_elapsed = 0.0
