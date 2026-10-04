class_name PixelationLayer
extends CanvasLayer

## Pixelates this layer before compositing it over the unfiltered background.
## Its world nodes retain the main Viewport's physics, input, and Z ordering.

const LAYER_SHADER: Shader = preload("./pixelation_layer.gdshader")

@export var pixelation: Pixelation:
	set(value):
		_disconnect_pixelation()
		pixelation = value
		if is_node_ready():
			_connect_pixelation()
			_update_material()

@export var post_processing: PostProcessing

var _main_viewport: Viewport
var _source_viewport: SubViewport
var _material: ShaderMaterial


func _ready() -> void:
	_main_viewport = get_viewport()
	_source_viewport = SubViewport.new()
	_source_viewport.name = "Source"
	_source_viewport.disable_3d = true
	_source_viewport.use_hdr_2d = true
	_source_viewport.transparent_bg = true
	_source_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_source_viewport.canvas_item_default_texture_filter = (
		_main_viewport.canvas_item_default_texture_filter
	)
	_source_viewport.canvas_item_default_texture_repeat = (
		_main_viewport.canvas_item_default_texture_repeat
	)
	add_child(_source_viewport, false, Node.INTERNAL_MODE_BACK)
	custom_viewport = _source_viewport
	follow_viewport_enabled = true
	_sync_viewport()

	# Keep the world nodes in the main Viewport for physics and input.
	# Only their canvas is rendered separately, including every Z index.
	var output := CanvasLayer.new()
	output.name = "Image"
	output.layer = RenderLayers.LAYER_1_OUTPUT
	add_child(output, false, Node.INTERNAL_MODE_BACK)
	output.custom_viewport = _main_viewport
	_material = ShaderMaterial.new()
	_material.shader = LAYER_SHADER
	_material.set_shader_parameter(&"layer_texture", _source_viewport.get_texture())
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = _material
	output.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_connect_pixelation()
	_update_material()


func _process(_delta: float) -> void:
	_sync_viewport()
	_update_enabled_state()


func _exit_tree() -> void:
	_disconnect_pixelation()


func _on_pixelation_changed() -> void:
	_update_material()


func _connect_pixelation() -> void:
	if pixelation != null:
		pixelation.changed.connect(_on_pixelation_changed)


func _disconnect_pixelation() -> void:
	if pixelation != null and pixelation.changed.is_connected(_on_pixelation_changed):
		pixelation.changed.disconnect(_on_pixelation_changed)


func _update_material() -> void:
	if pixelation != null:
		pixelation.apply_to(_material)
	_update_enabled_state()


func _update_enabled_state() -> void:
	_material.set_shader_parameter(&"pixelation_enabled", (
		pixelation != null and pixelation.enabled
		and (post_processing == null or post_processing.enabled)
	))


func _sync_viewport() -> void:
	var stretch := _main_viewport.get_stretch_transform()
	_source_viewport.size = Vector2i((_main_viewport.get_visible_rect().size * stretch.get_scale()).round())
	_source_viewport.canvas_transform = _main_viewport.canvas_transform
	_source_viewport.global_canvas_transform = stretch * _main_viewport.global_canvas_transform
	_source_viewport.snap_2d_transforms_to_pixel = _main_viewport.snap_2d_transforms_to_pixel
	_source_viewport.snap_2d_vertices_to_pixel = _main_viewport.snap_2d_vertices_to_pixel
