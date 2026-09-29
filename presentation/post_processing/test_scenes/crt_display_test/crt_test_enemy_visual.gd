class_name CRTTestEnemyVisual
extends Node2D

enum Shape {
	CIRCLE,
	TRIANGLE,
	SQUARE,
	DIAMOND,
	HEXAGON,
}

var shape: int = Shape.CIRCLE
var radius: float = 30.0
var body_color: Color = Color.WHITE


func configure(new_shape: int, new_radius: float, new_color: Color) -> void:
	shape = new_shape
	radius = new_radius
	body_color = new_color
	queue_redraw()


func _draw() -> void:
	if shape == Shape.CIRCLE:
		draw_circle(Vector2.ZERO, radius, body_color)
	else:
		var corners := 6
		if shape == Shape.TRIANGLE:
			corners = 3
		elif shape == Shape.SQUARE or shape == Shape.DIAMOND:
			corners = 4
		var angle_offset := 0.0
		if shape == Shape.TRIANGLE:
			angle_offset = -PI * 0.5
		elif shape == Shape.SQUARE:
			angle_offset = PI * 0.25
		var points := PackedVector2Array()
		for index in corners:
			points.append(Vector2.from_angle(TAU * float(index) / float(corners) + angle_offset) * radius)
		draw_colored_polygon(points, body_color)
