extends Node2D

@export_range(2.0, 64.0, 0.5, "suffix:px") var radius: float = 8.0:
	set(value):
		radius = value
		queue_redraw()
@export var tint: Color = Color("#62edc4")


func _draw() -> void:
	var thickness := radius * 0.16
	draw_circle(Vector2.ZERO, radius * 1.30, Color(tint, 0.10))
	draw_arc(Vector2.ZERO, radius + thickness * 0.6, 0.0, TAU, 40, tint, thickness)
