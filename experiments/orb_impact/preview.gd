extends Node

enum Mode {
	SPARK,
	RING,
	BOTH,
	OFF,
	RING_DISTORTION,
	DISTORTION,
	DROPLETS,
}

const IMPACT: PackedScene = preload("res://experiments/orb_impact/impact.tscn")
const WAVE_SHADER: Shader = preload("res://experiments/orb_impact/wave.gdshader")

@export var mode: Mode = Mode.SPARK
@export var ring_color: Color = Color(0.8, 0.95, 1.0, 0.48)
@export_range(0.0, 6.0, 0.25, "suffix:px") var distortion_strength: float = 2.5

var _slow_motion: bool = false
var _original_time_scale: float = 1.0
var _wave_material: ShaderMaterial
var _wave_layer: CanvasLayer
var _wave_copy: BackBufferCopy
var _wave_rect: ColorRect

@onready var _game: Main = $Main
@onready var _effects: Node2D = $Impacts
@onready var _status: Label = $Controls/Panel/Status


func _ready() -> void:
	_original_time_scale = Engine.time_scale
	_game.orb.sweep_hit.hurtbox_detected.connect(_on_hurtbox_detected)
	_create_wave_layer()
	_update_status()


func _process(_delta: float) -> void:
	var geometry: Array[Vector4] = []
	var behavior: Array[Vector4] = []
	var headings := PackedVector2Array()
	var canvas := _effects.get_canvas_transform()
	for impact: Node2D in _effects.get_children():
		if not impact.wave_enabled or impact.get_wave_fade() <= 0.0:
			continue
		if geometry.size() == 16:
			break
		var wave: Vector4 = impact.get_wave_geometry()
		var center := canvas * Vector2(wave.x, wave.y)
		var direction: Vector2 = impact.get_wave_direction()
		var axis := canvas.basis_xform(direction)
		var side := canvas.basis_xform(direction.orthogonal())
		geometry.append(Vector4(center.x, center.y, wave.z * axis.length(), wave.w * side.length()))
		behavior.append(Vector4(
			impact.get_wave_fade(), float(impact.ring_enabled),
			float(impact.distortion_enabled), 0.0
		))
		headings.append(axis.normalized())
	var count := geometry.size()
	_wave_copy.visible = count > 0
	_wave_rect.visible = count > 0
	if count == 0:
		return
	geometry.resize(16)
	behavior.resize(16)
	headings.resize(16)
	_wave_material.set_shader_parameter("wave_count", count)
	_wave_material.set_shader_parameter("geometry", geometry)
	_wave_material.set_shader_parameter("behavior", behavior)
	_wave_material.set_shader_parameter("heading", headings)
	_wave_material.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)
	_wave_material.set_shader_parameter("ring_color", ring_color)
	_wave_material.set_shader_parameter("displacement", distortion_strength)


func _exit_tree() -> void:
	Engine.time_scale = _original_time_scale


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			mode = Mode.SPARK
		KEY_2:
			mode = Mode.RING
		KEY_3:
			mode = Mode.BOTH
		KEY_0:
			mode = Mode.OFF
		KEY_4:
			_slow_motion = not _slow_motion
			Engine.time_scale = _original_time_scale * (0.25 if _slow_motion else 1.0)
		KEY_5:
			mode = Mode.RING_DISTORTION
		KEY_6:
			mode = Mode.DISTORTION
		KEY_7:
			mode = Mode.DROPLETS
		_:
			return
	_update_status()
	get_viewport().set_input_as_handled()


func _on_hurtbox_detected(hurtbox: Hurtbox, direction: Vector2) -> void:
	if mode == Mode.OFF:
		return
	# The experiment uses the existing circular enemy surface, including lethal hits.
	var collision_shape := hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var circle := collision_shape.shape as CircleShape2D
	var contact := hurtbox.global_position - direction * circle.radius
	var impact: Node2D = IMPACT.instantiate()
	_effects.add_child(impact)
	impact.global_position = contact
	impact.play(_game.orb.movement.heading, _game.orb.movement.velocity.length(), mode)


func _update_status() -> void:
	var names: Array[String] = [
		"SPARK", "RING", "SPARK + RING", "OFF", "RING + DISTORTION", "DISTORTION", "DROPLETS"
	]
	var controls := "\n1 Spark   2 Ring   3 Both   0 Off   4 Slow motion"
	controls += "\n5 Ring + distortion   6 Distortion   7 Droplets"
	_status.text = ("IMPACT LAB  /  %s  /  %s" + controls) % [
		names[mode], "0.25x" if _slow_motion else "1x"
	]


func _create_wave_layer() -> void:
	# A single capture/pass combines all waves before world post-processing and damage numbers.
	_wave_layer = CanvasLayer.new()
	_wave_layer.layer = RenderLayers.LAYER_1_OUTPUT
	add_child(_wave_layer)
	_wave_copy = BackBufferCopy.new()
	_wave_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_wave_layer.add_child(_wave_copy)
	_wave_material = ShaderMaterial.new()
	_wave_material.shader = WAVE_SHADER
	_wave_rect = ColorRect.new()
	_wave_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wave_rect.material = _wave_material
	_wave_layer.add_child(_wave_rect)
	_wave_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
