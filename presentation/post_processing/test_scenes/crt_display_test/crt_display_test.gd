@tool
extends Node2D

enum BackgroundStyle {
	SOLID,
	CHECKERBOARD,
	GRADIENT,
}

const CANVAS_SIZE: Vector2 = Vector2(1280.0, 720.0)
const BACKGROUND_CHECKER_SIZE: float = 32.0

@export var background_style: BackgroundStyle = BackgroundStyle.SOLID:
	set(value):
		if background_style == value:
			return
		background_style = value
		if is_inside_tree():
			queue_redraw()

@export var images: Array[Texture2D] = []:
	set(value):
		images = value
		if is_node_ready():
			if _image_index >= images.size() or (
				_image_index >= 0 and images[_image_index] == null
			):
				_show_pattern()
			else:
				queue_redraw()

var _image_index: int = -1
var _previous_content_scale_mode: int

@onready var _ui: Control = $WorldUILayer/UI
@onready var _world_ui_layer: CanvasLayer = $WorldUILayer


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var root_window := get_tree().root
	_previous_content_scale_mode = root_window.content_scale_mode
	get_viewport().size_changed.connect(_fit_canvas)
	root_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	_fit_canvas()
	call_deferred("_fit_canvas")
	_create_labels()
	_ui.visible = _image_index < 0


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	get_tree().root.content_scale_mode = _previous_content_scale_mode as Window.ContentScaleMode


func _draw() -> void:
	if _image_index >= 0:
		if _image_index < images.size() and images[_image_index] != null:
			draw_texture_rect(images[_image_index], Rect2(-position, get_viewport_rect().size), false)
			return
		_show_pattern()

	match background_style:
		BackgroundStyle.SOLID:
			draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.035, 0.04, 0.055))
		BackgroundStyle.CHECKERBOARD:
			_draw_background_checkerboard()
		BackgroundStyle.GRADIENT:
			_draw_background_gradient()

	draw_rect(Rect2(0.0, 0.0, CANVAS_SIZE.x, 65.0), Color(0.018, 0.021, 0.03))
	_draw_stripe_comparison()
	_draw_grayscale_comparison(Rect2(620.0, 98.0, 300.0, 175.0))
	_draw_color_comparison(Rect2(940.0, 98.0, 320.0, 175.0))
	_draw_alpha_comparison()
	_draw_gradients()
	_draw_hdr_objects()
	_draw_outline_comparison(20.0, 1.0)
	_draw_outline_comparison(320.0, 2.0)
	_draw_color_polygons()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			if _image_index >= 0:
				_show_pattern()
			else:
				background_style = (
					(background_style + 1) % BackgroundStyle.size()
				) as BackgroundStyle
		KEY_2:
			_show_next_image()
		_:
			return
	get_viewport().set_input_as_handled()


func _show_pattern() -> void:
	_image_index = -1
	_ui.show()
	queue_redraw()


func _show_next_image() -> void:
	for step in range(1, images.size() + 1):
		var next_index := (_image_index + step) % images.size()
		if images[next_index] != null:
			_image_index = next_index
			_ui.hide()
			queue_redraw()
			return
	_show_pattern()


func _create_labels() -> void:
	_add_label("CRT Display Experimental", Vector2(20.0, 7.0), 22)
	_add_label(
		"1  PATTERN / BACKGROUND: SOLID / CHECKER / GRADIENT   |   2  NEXT IMAGE",
		Vector2(20.0, 38.0),
		14
	)
	_add_label("STRIPES  |  COLUMNS: 2 / 3 / 4 / 5 / 6 / 7px   ROWS: V / H / DIAGONAL", Vector2(20.0, 73.0), 14)
	_add_label("GRAYSCALE  |  SMOOTH / 16 STEPS", Vector2(620.0, 73.0), 14)
	_add_label("COLOR  |  SMOOTH / 12 STEPS", Vector2(940.0, 73.0), 14)
	_add_label("ALPHA  |  BACKGROUND LUMINANCE / HUE / OVERLAP", Vector2(20.0, 293.0), 14)
	_add_label("COLOR GRADIENTS", Vector2(620.0, 293.0), 14)
	_add_label("HDR INPUT  |  1x / 2x / 4x / 8x / 16x", Vector2(940.0, 293.0), 14)
	_add_label("1px OUTLINES  |  O / 3 / 5 / 7", Vector2(20.0, 530.0), 14)
	_add_label("2px OUTLINES  |  O / 3 / 5 / 7", Vector2(320.0, 530.0), 14)
	_add_label("UI / TEXT", Vector2(620.0, 530.0), 14)
	_add_label("COLOR POLYGONS  |  VIVID / MUTED", Vector2(940.0, 530.0), 14)
	_add_label("12px thin  012345  abcXYZ", Vector2(625.0, 559.0), 12)
	_add_label("18px normal  012345", Vector2(625.0, 581.0), 18)
	_add_label("26px outline  012345", Vector2(625.0, 612.0), 26, Color.WHITE, 2)
	_add_label("34px LARGE  012345", Vector2(625.0, 656.0), 34)


func _add_label(
	label_text: String,
	label_position: Vector2,
	font_size: int,
	font_color: Color = Color(0.9, 0.92, 0.96),
	outline_size: int = 0,
) -> Label:
	var label := Label.new()
	label.text = label_text
	label.position = label_position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	if outline_size > 0:
		label.add_theme_constant_override("outline_size", outline_size)
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025))
	_ui.add_child(label)
	return label


func _fit_canvas() -> void:
	var viewport_size := get_viewport_rect().size
	var canvas_offset := ((viewport_size - CANVAS_SIZE) * 0.5).floor()
	scale = Vector2.ONE
	position = canvas_offset
	_world_ui_layer.transform = Transform2D(
		Vector2.RIGHT,
		Vector2.DOWN,
		canvas_offset
	)
	queue_redraw()


func _draw_background_checkerboard() -> void:
	for row in int(ceil(CANVAS_SIZE.y / BACKGROUND_CHECKER_SIZE)):
		for column in int(ceil(CANVAS_SIZE.x / BACKGROUND_CHECKER_SIZE)):
			var cell_color := Color(0.11, 0.13, 0.17)
			if (row + column) % 2 != 0:
				cell_color = Color(0.18, 0.21, 0.27)
			draw_rect(
				Rect2(Vector2(column, row) * BACKGROUND_CHECKER_SIZE, Vector2.ONE * BACKGROUND_CHECKER_SIZE),
				cell_color
			)


func _draw_background_gradient() -> void:
	const STRIP_HEIGHT: float = 4.0
	var strip_count := int(CANVAS_SIZE.y / STRIP_HEIGHT)
	for row in strip_count:
		var blend := float(row) / float(strip_count - 1)
		var gradient_color := Color.from_hsv(blend, 0.7, 0.45)
		draw_rect(Rect2(0.0, float(row) * STRIP_HEIGHT, CANVAS_SIZE.x, STRIP_HEIGHT), gradient_color)


func _draw_stripe_comparison() -> void:
	var widths: Array[int] = [2, 3, 4, 5, 6, 7]
	for row in 3:
		for column in widths.size():
			var rect := Rect2(20.0 + float(column) * 97.0, 98.0 + float(row) * 60.0, 90.0, 55.0)
			draw_rect(rect, Color(0.08, 0.1, 0.14))
			_draw_stripes(rect, widths[column], row)


func _draw_stripes(rect: Rect2, width: int, direction: int) -> void:
	var light := Color(0.76, 0.79, 0.83)
	if direction == 0:
		for x in int(rect.size.x):
			if floori(float(x) / float(width)) % 2 == 0:
				draw_rect(Rect2(rect.position + Vector2(x, 0.0), Vector2(1.0, rect.size.y)), light)
	elif direction == 1:
		for y in int(rect.size.y):
			if floori(float(y) / float(width)) % 2 == 0:
				draw_rect(Rect2(rect.position + Vector2(0.0, y), Vector2(rect.size.x, 1.0)), light)
	else:
		for y in int(rect.size.y):
			for x in int(rect.size.x):
				if floori(float(x + y) / float(width)) % 2 == 0:
					draw_rect(Rect2(rect.position + Vector2(x, y), Vector2.ONE), light)


func _draw_caption(label_text: String, caption_position: Vector2) -> void:
	draw_string(ThemeDB.fallback_font, caption_position + Vector2(0.0, 12.0), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12)


func _draw_grayscale_comparison(rect: Rect2) -> void:
	var half_height := rect.size.y / 2.0
	for column in int(rect.size.x):
		var level := float(column) / (rect.size.x - 1.0)
		draw_rect(Rect2(rect.position + Vector2(column, 0.0), Vector2(1.0, half_height)), Color(level, level, level))
	for step in 16:
		var level := float(step) / 15.0
		var left := rect.position.x + float(step) * rect.size.x / 16.0
		var right := rect.position.x + float(step + 1) * rect.size.x / 16.0
		draw_rect(Rect2(left, rect.position.y + half_height, right - left, half_height), Color(level, level, level))


func _draw_color_comparison(rect: Rect2) -> void:
	var half_height := rect.size.y / 2.0
	for column in int(rect.size.x):
		var hue := float(column) / (rect.size.x - 1.0)
		draw_rect(
			Rect2(rect.position.x + column, rect.position.y, 1.0, half_height),
			Color.from_hsv(hue, 0.85, 0.9)
		)
	for step in 12:
		var hue := (float(step) + 0.5) / 12.0
		var left := rect.position.x + float(step) * rect.size.x / 12.0
		var right := rect.position.x + float(step + 1) * rect.size.x / 12.0
		draw_rect(
			Rect2(left, rect.position.y + half_height, right - left, half_height),
			Color.from_hsv(hue, 0.85, 0.9)
		)


func _draw_alpha_comparison() -> void:
	var overlay := Color(0.12, 0.78, 0.67, 0.5)
	draw_rect(Rect2(20.0, 325.0, 90.0, 180.0), Color(0.06, 0.07, 0.1))
	draw_rect(Rect2(110.0, 325.0, 90.0, 180.0), Color(0.78, 0.8, 0.83))
	draw_rect(Rect2(44.0, 375.0, 132.0, 95.0), overlay)
	_draw_caption("DARK / LIGHT  50%", Vector2(28.0, 330.0))

	draw_rect(Rect2(215.0, 325.0, 90.0, 180.0), Color(0.7, 0.22, 0.12))
	draw_rect(Rect2(305.0, 325.0, 90.0, 180.0), Color(0.11, 0.32, 0.72))
	draw_rect(Rect2(239.0, 375.0, 132.0, 95.0), overlay)
	_draw_caption("WARM / COOL  50%", Vector2(223.0, 330.0))

	draw_rect(Rect2(410.0, 325.0, 180.0, 180.0), Color(0.24, 0.25, 0.28))
	draw_circle(Vector2(472.0, 425.0), 48.0, Color(0.95, 0.15, 0.6, 0.5))
	draw_circle(Vector2(528.0, 425.0), 48.0, Color(0.12, 0.85, 0.9, 0.5))
	_draw_caption("OVERLAP  50% + 50%", Vector2(418.0, 330.0))


func _draw_polygon(center: Vector2, radius: float, sides: int, angle_offset: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in sides:
		var angle := angle_offset + TAU * float(index) / float(sides)
		points.append(center + Vector2.RIGHT.rotated(angle) * radius)
	draw_colored_polygon(points, color)


func _draw_gradients() -> void:
	_draw_caption("BRIGHTNESS, SAME HUE", Vector2(630.0, 311.0))
	_draw_caption("SATURATION, SAME VALUE", Vector2(630.0, 376.0))
	for column in 280:
		var amount := float(column) / 279.0
		var brightness := Color.from_hsv(0.06, 0.7, lerpf(0.1, 1.0, amount))
		var saturation := Color.from_hsv(0.62, 1.0 - amount, 0.7)
		draw_rect(Rect2(630.0 + column, 325.0, 1.0, 48.0), brightness)
		draw_rect(Rect2(630.0 + column, 390.0, 1.0, 48.0), saturation)
	var warm_light := Color(1.0, 0.75, 0.32)
	var warm_dark := Color(0.08, 0.025, 0.02)
	_draw_radial_gradient(Vector2(659.0, 475.0), warm_light, warm_dark)
	_draw_radial_gradient(Vector2(733.0, 475.0), warm_dark, warm_light)
	_draw_radial_gradient(Vector2(807.0, 475.0), Color(0.8, 0.2, 0.25), Color(0.1, 0.42, 0.45))
	_draw_radial_gradient(
		Vector2(881.0, 475.0),
		Color.from_hsv(0.78, 0.9, 0.7),
		Color.from_hsv(0.78, 0.1, 0.7)
	)
	_draw_caption("LIGHT", Vector2(639.0, 499.0))
	_draw_caption("REVERSE", Vector2(706.0, 499.0))
	_draw_caption("HUE", Vector2(794.0, 499.0))
	_draw_caption("SAT", Vector2(870.0, 499.0))


func _draw_radial_gradient(center: Vector2, inner: Color, outer: Color) -> void:
	for step in range(23, 0, -1):
		var amount := 1.0 - float(step) / 23.0
		draw_circle(center, float(step), outer.lerp(inner, amount))


func _draw_hdr_objects() -> void:
	var levels: Array[float] = [1.0, 2.0, 4.0, 8.0, 16.0]
	_draw_caption("GRAY", Vector2(944.0, 350.0))
	_draw_caption("COLOR", Vector2(944.0, 435.0))
	for index in levels.size():
		var x := 1002.0 + float(index) * 51.0
		var level := levels[index]
		# CanvasItem draw colors are sRGB inputs; keep the intended linear HDR levels.
		var gray := Color(level, level, level, 1.0).linear_to_srgb()
		var color := Color(level, 0.3 * level, 0.1 * level, 1.0).linear_to_srgb()
		draw_rect(Rect2(x, 335.0, 42.0, 42.0), gray)
		draw_rect(Rect2(x, 420.0, 42.0, 42.0), color)
		_draw_caption("%dx" % int(level), Vector2(x + 7.0, 380.0))
		_draw_caption("%dx" % int(level), Vector2(x + 7.0, 465.0))


func _draw_outline_comparison(left: float, line_width: float) -> void:
	var angles: Array[float] = [0.0, 15.0, 30.0, 45.0]
	var sides: Array[int] = [0, 3, 5, 7]
	for index in angles.size():
		var x := left + 38.0 + float(index) * 67.0
		var color := Color(0.9, 0.93, 0.98)
		if sides[index] == 0:
			draw_arc(Vector2(x, 591.0), 17.0, 0.0, TAU, 72, color, line_width, false)
		else:
			_draw_outline_polygon(Vector2(x, 591.0), 19.0, sides[index], -PI / 2.0, color, line_width)
		for corner in 4:
			var angle := deg_to_rad(45.0 + angles[index] + float(corner) * 90.0)
			var next_angle := angle + PI / 2.0
			var center := Vector2(x, 651.0)
			draw_line(
				center + Vector2.RIGHT.rotated(angle) * 24.0,
				center + Vector2.RIGHT.rotated(next_angle) * 24.0,
				color,
				line_width,
				false
			)
		_draw_caption("%d deg" % int(angles[index]), Vector2(x - 19.0, 677.0))


func _draw_outline_polygon(
	center: Vector2,
	radius: float,
	sides: int,
	angle_offset: float,
	color: Color,
	line_width: float,
) -> void:
	for index in sides:
		var angle := angle_offset + TAU * float(index) / float(sides)
		var next_angle := angle_offset + TAU * float(index + 1) / float(sides)
		draw_line(
			center + Vector2.RIGHT.rotated(angle) * radius,
			center + Vector2.RIGHT.rotated(next_angle) * radius,
			color,
			line_width,
			false
		)


func _draw_color_polygons() -> void:
	var colors: Array[Color] = [
		Color(0.95, 0.08, 0.08), Color(0.08, 0.9, 0.2), Color(0.1, 0.25, 0.95), Color(0.95, 0.82, 0.14),
		Color(0.84, 0.62, 0.64), Color(0.62, 0.74, 0.85), Color(0.58, 0.55, 0.43), Color(0.4, 0.56, 0.5),
	]
	for index in colors.size():
		var center := Vector2(983.0 + float(index % 4) * 79.0, 592.0 + float(floori(float(index) / 4.0)) * 70.0)
		var sides := 3 + index % 4
		var angle_offset := -PI / 2.0
		if index >= 4:
			angle_offset += PI / 12.0
		_draw_polygon(center, 25.0, sides, angle_offset, colors[index])
