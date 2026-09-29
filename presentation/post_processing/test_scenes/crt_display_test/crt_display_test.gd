@tool
extends Node2D

enum BackgroundStyle {
	SOLID,
	CHECKERBOARD,
	GRADIENT,
}

const CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const CHECKER_SIZE: float = 48.0

@export var background_style: BackgroundStyle = BackgroundStyle.SOLID:
	set(value):
		if background_style == value:
			return
		background_style = value
		if is_inside_tree():
			queue_redraw()


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_fit_canvas()
	get_viewport().size_changed.connect(_fit_canvas)


func _draw() -> void:
	match background_style:
		BackgroundStyle.SOLID:
			draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.11, 0.13, 0.17))
		BackgroundStyle.CHECKERBOARD:
			_draw_checkerboard()
		BackgroundStyle.GRADIENT:
			_draw_gradient()


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_B:
		return
	match background_style:
		BackgroundStyle.SOLID:
			background_style = BackgroundStyle.CHECKERBOARD
		BackgroundStyle.CHECKERBOARD:
			background_style = BackgroundStyle.GRADIENT
		BackgroundStyle.GRADIENT:
			background_style = BackgroundStyle.SOLID


func _draw_checkerboard() -> void:
	for row in int(ceil(CANVAS_SIZE.y / CHECKER_SIZE)):
		for column in int(ceil(CANVAS_SIZE.x / CHECKER_SIZE)):
			var cell_color := Color(0.18, 0.21, 0.27)
			if (row + column) % 2 != 0:
				cell_color = Color(0.27, 0.3, 0.37)
			draw_rect(
				Rect2(Vector2(column, row) * CHECKER_SIZE, Vector2.ONE * CHECKER_SIZE),
				cell_color
			)


func _draw_gradient() -> void:
	const STRIP_WIDTH: float = 5.0
	var strip_count := int(CANVAS_SIZE.x / STRIP_WIDTH)
	for column in strip_count:
		var blend := float(column) / float(strip_count - 1)
		var gradient_color := Color(0.07, 0.13, 0.32).lerp(Color(0.78, 0.52, 0.34), blend)
		draw_rect(
			Rect2(float(column) * STRIP_WIDTH, 0.0, STRIP_WIDTH, CANVAS_SIZE.y),
			gradient_color
		)


func _fit_canvas() -> void:
	scale = get_viewport_rect().size / CANVAS_SIZE
