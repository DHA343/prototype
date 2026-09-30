@tool
extends Node2D

const CANVAS_SIZE: Vector2 = Vector2(1280.0, 720.0)

var _elapsed: float = 0.0
var _motion_enabled: bool = true
var _previous_content_scale_mode: int

@onready var _post_processing: PostProcessing = $PostProcessing
@onready var _crt: CRTDisplayExperimental = _post_processing.composite_effects[0] as CRTDisplayExperimental


func _ready() -> void:
	if not Engine.is_editor_hint():
		var root_window := get_tree().root
		_previous_content_scale_mode = root_window.content_scale_mode
		get_viewport().size_changed.connect(_fit_canvas)
		root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		_fit_canvas()
		call_deferred("_fit_canvas")


func _exit_tree() -> void:
	if not Engine.is_editor_hint():
		get_tree().root.content_scale_mode = _previous_content_scale_mode as Window.ContentScaleMode


func _process(delta: float) -> void:
	if not Engine.is_editor_hint() and _motion_enabled:
		_elapsed += delta
	queue_redraw()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			_crt.phosphor_bloom_mode = (
				CRTDisplayExperimental.BloomMode.LIMITED
				if _crt.phosphor_bloom_mode == CRTDisplayExperimental.BloomMode.LINEAR
				else CRTDisplayExperimental.BloomMode.LINEAR
			)
		KEY_2:
			_crt.phosphor_bloom_enabled = not _crt.phosphor_bloom_enabled
		KEY_3:
			_motion_enabled = not _motion_enabled


func _draw() -> void:
	draw_rect(Rect2(-position, get_viewport_rect().size), Color(0.005, 0.005, 0.005))
	_caption("Phosphor Bloom - linear HDR / edges / motion", Vector2(30.0, 35.0), 24)
	var mode := "LIMITED (A)" if _crt.phosphor_bloom_mode == CRTDisplayExperimental.BloomMode.LIMITED else "LINEAR (B)"
	var state := "ON" if _crt.phosphor_bloom_enabled else "OFF"
	_caption("1  MODE: %s    2  BLOOM: %s    3  MOTION" % [mode, state], Vector2(30.0, 65.0))
	_caption("RGB values below are linear HDR; draw colors are encoded to sRGB.", Vector2(30.0, 88.0), 14)

	var levels: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]
	for index in levels.size():
		var level := levels[index]
		var x := 80.0 + float(index) * 100.0
		draw_rect(Rect2(x, 120.0, 64.0, 64.0), _draw_color(Color(level, level, level, 1.0)))
		draw_rect(Rect2(x, 230.0, 64.0, 64.0), _draw_color(Color(level, 0.3 * level, 0.1 * level, 1.0)))
		_caption("%dx" % int(level), Vector2(x + 18.0, 205.0), 14)
		_caption("%dx" % int(level), Vector2(x + 18.0, 315.0), 14)
	_caption("GRAY", Vector2(30.0, 153.0), 14)
	_caption("COLOR", Vector2(20.0, 264.0), 14)

	_caption("1px LINES / SMALL TEXT", Vector2(80.0, 365.0))
	# Several phases expose reconstruction of a 1px line relative to the scanlines.
	for index in 3:
		var y := 390.0 + float(index) * 7.0
		draw_line(Vector2(80.0, y), Vector2(540.0, y), Color.WHITE, 1.0)
	draw_line(Vector2(600.0, 130.0), Vector2(600.0, 315.0), Color.WHITE, 1.0)
	_caption("10px  abcXYZ  012345", Vector2(80.0, 420.0), 10)
	_caption("12px  abcXYZ  012345", Vector2(80.0, 445.0), 12)
	_caption("16px  abcXYZ  012345", Vector2(80.0, 475.0), 16)

	_caption("WHITE POINTS  1 / 2 / 4px", Vector2(680.0, 125.0))
	for index in 3:
		var size := pow(2.0, float(index))
		draw_rect(Rect2(740.0 + float(index) * 150.0, 160.0, size, size), Color.WHITE)
	_caption("RGB SINGLE CHANNEL / 4x", Vector2(680.0, 240.0))
	var colors: Array[Color] = [Color(4.0, 0.0, 0.0), Color(0.0, 4.0, 0.0), Color(0.0, 0.0, 4.0)]
	for index in colors.size():
		draw_rect(Rect2(710.0 + float(index) * 150.0, 270.0, 64.0, 64.0), _draw_color(colors[index]))

	_caption("UNIFORM BRIGHT AREA / 2x", Vector2(80.0, 535.0))
	draw_rect(Rect2(80.0, 550.0, 450.0, 120.0), _draw_color(Color(2.0, 2.0, 2.0)))
	_caption("MOVING POINT / 8x", Vector2(680.0, 535.0))
	var moving_x := 700.0 + 430.0 * (0.5 + 0.5 * sin(_elapsed))
	draw_rect(Rect2(moving_x, 590.0, 2.0, 2.0), _draw_color(Color(8.0, 8.0, 8.0)))

	var viewport_size := get_viewport_rect().size
	draw_rect(Rect2(-position.x, 349.0, 2.0, 2.0), _draw_color(Color(8.0, 8.0, 8.0)))
	draw_rect(Rect2(viewport_size.x - position.x - 2.0, 349.0, 2.0, 2.0), _draw_color(Color(8.0, 8.0, 8.0)))
	_caption("EDGE POINTS", Vector2(1090.0, 390.0), 14)


func _fit_canvas() -> void:
	position = ((get_viewport_rect().size - CANVAS_SIZE) * 0.5).floor()


func _draw_color(linear_color: Color) -> Color:
	# CanvasItem draw colors are sRGB inputs even when the target stores linear HDR.
	return linear_color.linear_to_srgb()


func _caption(text: String, baseline: Vector2, font_size: int = 18) -> void:
	draw_string(ThemeDB.fallback_font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
