@tool
class_name CircleVisual
extends Node2D

@export_range(0.0, 100.0, 1.0, "suffix:px") var radius: float = 40.0:
	set(value):
		radius = maxf(value, 0.0)
		queue_redraw()

@export var aspect_ratio: Vector2 = Vector2.ONE:
	set(value):
		aspect_ratio = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
		queue_redraw()

@export var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()

@export_range(0.0, 10.0, 0.1, "suffix:px") var outline_width: float = 0.0:
	set(value):
		outline_width = maxf(value, 0.0)
		queue_redraw()

@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, aspect_ratio)
	draw_circle(Vector2.ZERO, radius, color)

	if outline_width > 0.0 and outline_color.a > 0.0:
		draw_circle(Vector2.ZERO, radius, outline_color, false, outline_width, true)
