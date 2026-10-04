@tool
extends Node2D

enum Source {
	MAIN,
	PATTERN,
	IMAGE,
}

const IMAGE_DIRECTORY: String = "res://experiments/post_processing/testbed/images"
const IMAGE_EXTENSIONS: Array[String] = [
	"png", "jpg", "jpeg", "webp", "bmp", "svg", "tga", "exr", "hdr", "dds", "ktx", "ktx2",
]

@export var main_scene: PackedScene = preload("res://main/main.tscn")
@export var mask_image: Texture2D
@export var velocity_image: Texture2D
@export var mask_orb: bool = true
@export var mask_enemies: bool = true

var source: Source = Source.MAIN
var _main: Node2D
var _main_layers: Dictionary[CanvasLayer, bool] = {}
var _modes: Dictionary[ExperimentEffect, int] = {}
var _buffers: Array[SubViewport] = []

@onready var _post: PostProcessing = $PostProcessing
@onready var _pattern: Node2D = $Layer1/Content
@onready var _layer_1: CanvasLayer = $Layer1
@onready var _pattern_labels: Node2D = $Layer2/Labels


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_pattern.set("images", _collect_images(IMAGE_DIRECTORY))
	_watch_effects()
	_create_buffers()
	select_source(Source.MAIN)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_watch_effects()
	var needed := false
	for effect in _post.layer_1_effects + _post.layer_2_effects:
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
			select_source(Source.PATTERN)
		KEY_3:
			next_image()
		_:
			return
	get_viewport().set_input_as_handled()


func select_source(value: Source) -> void:
	if value == Source.MAIN and _main == null:
		_main = main_scene.instantiate() as Node2D
		var main_post := _main.get_node_or_null("PostProcessing") as PostProcessing
		if main_post != null:
			main_post.layer_1_effects = []
			main_post.layer_2_effects = []
			main_post.enabled = false
		var layer_1 := _main.get_node_or_null("Layer1") as PixelationLayer
		if layer_1 != null:
			layer_1.post_processing = _post
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
	_layer_1.visible = not show_main
	_pattern_labels.visible = value == Source.PATTERN
	if value == Source.PATTERN:
		_pattern.call("_show_pattern")
	for effect in _post.layer_1_effects + _post.layer_2_effects:
		if effect is ExperimentEffect:
			(effect as ExperimentEffect).reset_history()
	for viewport in _buffers:
		viewport.get_child(0).call("reset_motion")


func next_image() -> void:
	_pattern.call("_show_next_image")
	select_source(Source.IMAGE if int(_pattern.get("_image_index")) >= 0 else Source.PATTERN)


func _collect_images(directory: String) -> Array[Texture2D]:
	var images: Array[Texture2D] = []
	if not DirAccess.dir_exists_absolute(directory):
		return images
	var files := ResourceLoader.list_directory(directory)
	files.sort()
	for file in files:
		if file.ends_with("/") or file.get_extension().to_lower() not in IMAGE_EXTENSIONS:
			continue
		var path := directory.path_join(file)
		var texture := load(path) as Texture2D
		if texture != null:
			images.append(texture)
	return images


func _on_effect_changed(effect: ExperimentEffect) -> void:
	if not _modes.has(effect):
		return
	var mode := int(effect.get_parameter(&"mode"))
	if _modes[effect] != mode:
		_modes[effect] = mode
		_post.rebuild_effects()


func _watch_effects() -> void:
	for effect in _post.layer_1_effects + _post.layer_2_effects:
		if effect is ExperimentEffect:
			var experiment := effect as ExperimentEffect
			if not _modes.has(experiment):
				_modes[experiment] = int(experiment.get_parameter(&"mode"))
				experiment.changed.connect(_on_effect_changed.bind(experiment), CONNECT_DEFERRED)
	for experiment: ExperimentEffect in _modes.keys():
		if not _post.layer_1_effects.has(experiment) and not _post.layer_2_effects.has(experiment):
			experiment.changed.disconnect(_on_effect_changed.bind(experiment))
			_modes.erase(experiment)


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
