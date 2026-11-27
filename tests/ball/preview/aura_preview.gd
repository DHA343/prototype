extends Control

const Ball = preload("res://tests/ball/ball.gd")
const BallAfterimage = preload("res://tests/ball/preview/ball_afterimage.gd")
const AfterimageStyle = preload("res://tests/ball/preview/afterimage_style.gd")
const BALL_SCENE: PackedScene = preload("res://tests/ball/ball.tscn")
const MAIN_SCENE: PackedScene = preload("res://main/main.tscn")
const VIEW_SIZE := Vector2i(1920, 1080)
const VIEW_RESOLUTION := Vector2i(640, 360)
const BOARD_REGION := Rect2(156, 0, 328, 360)

@export_group("Afterimage Style")
## The first color is also used by the flat variant.
@export var color_gradient: Gradient
@export_range(0.04, 0.40, 0.01, "suffix:s") var lifetime: float = 0.16
## Time each circle keeps its initial radius.
@export_range(0.0, 0.40, 0.01, "suffix:s") var width_hold: float = 0.04
## Root width relative to the ball diameter.
@export_range(0.50, 1.50, 0.05, "suffix:×") var width_scale: float = 0.95
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.88
## Fraction of the lifetime that keeps the first color.
@export_range(0.0, 0.80, 0.01) var root_color_hold: float = 0.28
## How strongly the rim shifts toward the last color.
@export_range(0.0, 1.0, 0.01) var edge_color_strength: float = 1.0

var _afterimage_style: AfterimageStyle
var _arenas: Array[PinballLab]
var _reset_held: bool

@onready var _boards: HBoxContainer = $Layout/Boards


func _ready() -> void:
	_afterimage_style = AfterimageStyle.new()
	if color_gradient != null:
		_afterimage_style.color_gradient = color_gradient
	_afterimage_style.lifetime = lifetime
	_afterimage_style.width_hold = width_hold
	_afterimage_style.width_scale = width_scale
	_afterimage_style.opacity = opacity
	_afterimage_style.root_color_hold = root_color_hold
	_afterimage_style.edge_color_strength = edge_color_strength

	_add_arena("Flat color", false)
	_add_arena("Both gradients", true)


func _physics_process(delta: float) -> void:
	var reset_pressed := Input.is_physical_key_pressed(KEY_R) or Input.is_key_pressed(KEY_R)
	if reset_pressed:
		if not _reset_held:
			for arena in _arenas:
				arena.reset_ball()
	else:
		for arena in _arenas:
			arena.advance(delta)
	_reset_held = reset_pressed


func _add_arena(heading: String, gradients: bool) -> void:
	var view := _create_board(heading)
	var arena := MAIN_SCENE.instantiate() as PinballLab
	var playfield := arena.get_node("Playfield")
	var original := playfield.get_node("Ball") as PinballBall
	var ball := BALL_SCENE.instantiate() as Ball
	ball.transform = original.transform
	ball.radius = original.radius
	ball.gravity = original.gravity
	ball.max_speed = original.max_speed
	ball.outline_enabled = true

	var ball_index := original.get_index()
	playfield.remove_child(original)
	original.free()
	playfield.add_child(ball)
	playfield.move_child(ball, ball_index)

	var afterimage := BallAfterimage.new()
	afterimage.name = "Afterimage"
	afterimage.ball = ball
	afterimage.radius = ball.radius
	afterimage.gradient_enabled = gradients
	afterimage.style = _afterimage_style
	playfield.add_child(afterimage)
	playfield.move_child(afterimage, ball.get_index())
	ball.traveled.connect(afterimage.record_travel)
	ball.repositioned.connect(afterimage.clear)

	var spawner := arena.get_node("EnemySpawner") as EnemySpawner
	spawner.enabled = false
	var launcher := playfield.get_node("MissileLauncher") as MissileLauncher
	launcher.volley_size = 0
	playfield.get_node("DebugSummon").set_process_unhandled_key_input(false)
	view.add_child(arena)
	arena.set_physics_process(false)
	_arenas.append(arena)


func _create_board(heading: String) -> SubViewport:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 10)
	_boards.add_child(column)

	var title := Label.new()
	title.text = heading
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override(&"font_size", 30)
	column.add_child(title)

	var view := SubViewport.new()
	view.size = VIEW_RESOLUTION
	view.size_2d_override = VIEW_SIZE
	view.size_2d_override_stretch = true
	view.disable_3d = true
	view.use_hdr_2d = true
	view.audio_listener_enable_2d = _arenas.is_empty()
	view.world_2d = World2D.new()
	column.add_child(view)

	# Crop the outside of the cabinet while keeping the playfield at its normal scale.
	var crop := AtlasTexture.new()
	crop.atlas = view.get_texture()
	crop.region = BOARD_REGION
	crop.filter_clip = true
	var display := TextureRect.new()
	display.custom_minimum_size = Vector2(0.0, 740.0)
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	display.texture = crop
	column.add_child(display)
	return view
