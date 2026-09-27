class_name ShockwaveVisual
extends Node2D

@export var fill_color: Color = Color(0.35, 0.8, 1.0, 0.18)
@export var outline_color: Color = Color(0.65, 0.95, 1.0, 0.9)
@export_range(0.1, 20.0, 0.1, "suffix:px") var outline_width: float = 4.0

var _radius: float = 0.0


func _draw() -> void:
	if _radius <= 0.0:
		return
	draw_circle(Vector2.ZERO, _radius, fill_color)
	draw_circle(Vector2.ZERO, _radius, outline_color, false, outline_width, true)


func set_radius(radius: float) -> void:
	_radius = maxf(radius, 0.0)
	queue_redraw()
