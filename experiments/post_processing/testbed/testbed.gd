@tool
extends Node2D

enum Source {
	MAIN,
	PATTERN,
	IMAGE,
}

@export var preview_title: String = "Post-process Testbed"
@export var main_scene: PackedScene = preload("res://main/main.tscn")
@export var images: Array[Texture2D] = []
@export var mask_image: Texture2D
@export var velocity_image: Texture2D
@export var mask_orb: bool = true
@export var mask_enemies: bool = true

var source: Source = Source.MAIN
var _main: Node2D
var _main_layers: Dictionary[CanvasLayer, bool] = {}
var _panel: Control
var _buffers: Array[SubViewport] = []

@onready var _post: PostProcessing = $PostProcessing
@onready var _pattern: Node2D = $Pattern/Content
@onready var _pattern_layer: CanvasLayer = $Pattern
@onready var _pattern_ui: CanvasLayer = $WorldUILayer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_pattern.set("images", images)
	_pattern.set("preview_title", preview_title)
	var layer := CanvasLayer.new()
	layer.layer = 1000
	add_child(layer)
	_panel = preload("panel.gd").new()
	_panel.testbed = self
	layer.add_child(_panel)
	_create_buffers()
	select_source(Source.MAIN)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var needed := false
	for effect in _post.world_effects + _post.composite_effects:
		if effect is ExperimentEffect:
			var experiment := effect as ExperimentEffect
			for uniform: Dictionary in experiment.get_shader().get_shader_uniform_list():
				if uniform.name in ["mask_texture", "velocity_texture"] and effect.enabled:
					needed = true
			experiment.set_runtime_parameter(&"mask_texture", mask_image if mask_image != null else _buffers[0].get_texture())
			experiment.set_runtime_parameter(&"velocity_texture", velocity_image if velocity_image != null else _buffers[1].get_texture())
	for viewport in _buffers:
		viewport.size = Vector2i(get_viewport_rect().size).max(Vector2i.ONE)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if needed and _post.enabled else SubViewport.UPDATE_DISABLED


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	match key.keycode:
		KEY_1:
			select_source(Source.MAIN)
		KEY_2:
			if source == Source.PATTERN:
				_pattern.set("background_style", (int(_pattern.get("background_style")) + 1) % 3)
			select_source(Source.PATTERN)
		KEY_3:
			next_image()
		KEY_F1:
			_panel.visible = not _panel.visible
		KEY_O:
			if not key.ctrl_pressed:
				return
			_panel.call("open_file", "image")
		_:
			return
	get_viewport().set_input_as_handled()


func select_source(value: Source) -> void:
	if value == Source.MAIN and _main == null:
		_main = main_scene.instantiate() as Node2D
		var main_post := _main.get_node_or_null("PostProcessing") as PostProcessing
		if main_post != null:
			main_post.world_effects = []
			main_post.composite_effects = []
			main_post.enabled = false
		var world := _main.get_node_or_null("WorldLayer") as PixelationLayer
		if world != null:
			world.post_processing = _post
		add_child(_main)
		for node in _main.find_children("*", "CanvasLayer", true, false):
			var layer := node as CanvasLayer
			_main_layers[layer] = layer.visible
	source = value
	var show_main := value == Source.MAIN
	if _main != null:
		_main.visible = show_main
		_main.process_mode = Node.PROCESS_MODE_INHERIT if show_main else Node.PROCESS_MODE_DISABLED
		for layer: CanvasLayer in _main_layers:
			if is_instance_valid(layer):
				layer.visible = show_main and _main_layers[layer]
		var camera := _main.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.enabled = show_main
	_pattern_layer.visible = not show_main
	_pattern_ui.visible = value == Source.PATTERN
	if value == Source.PATTERN:
		_pattern.call("_show_pattern")
	for effect in _post.world_effects + _post.composite_effects:
		if effect is ExperimentEffect:
			(effect as ExperimentEffect).reset_history()
	for viewport in _buffers:
		viewport.get_child(0).call("reset_motion")
	if _panel != null:
		_panel.call("set_status", "%s | 1 Main / 2 Pattern / 3 Image / F1 Panel" % Source.keys()[value])


func next_image() -> void:
	_pattern.call("_show_next_image")
	select_source(Source.IMAGE if int(_pattern.get("_image_index")) >= 0 else Source.PATTERN)


func _create_buffers() -> void:
	for mode in 2:
		var viewport := SubViewport.new()
		viewport.disable_3d = true
		viewport.use_hdr_2d = true
		viewport.size = Vector2i(get_viewport_rect().size).max(Vector2i.ONE)
		viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		add_child(viewport)
		_buffers.append(viewport)
		var canvas := preload("buffers.gd").new()
		canvas.testbed = self
		canvas.mode = mode
		viewport.add_child(canvas)
