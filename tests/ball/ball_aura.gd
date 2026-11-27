extends Node2D

const FULL_SPEED: float = 900.0
const MAX_LENGTH: float = 2.8

@export_range(2.0, 64.0, 0.5, "suffix:px") var radius: float = 8.0:
	set(value):
		radius = value
		queue_redraw()
@export var tint: Color = Color("#62edc4")

var _extension: float


func _draw() -> void:
	if is_zero_approx(_extension):
		return
	var root := -radius * 0.52
	var shoulder := -radius * (0.9 + _extension * 0.30)
	var tip := -radius * (1.0 + _extension)
	var corners := PackedVector2Array([
		Vector2(tip, 0.0),
		Vector2(shoulder, radius * 0.37),
		Vector2(root, radius * 0.68),
		Vector2(root, -radius * 0.68),
		Vector2(shoulder, -radius * 0.37),
	])
	var colors := PackedColorArray([
		Color(tint, 0.0), Color(tint, tint.a * 0.42), Color(tint, tint.a * 0.78),
		Color(tint, tint.a * 0.78), Color(tint, tint.a * 0.42),
	])
	draw_polygon(corners, colors)


func set_velocity(velocity: Vector2) -> void:
	_extension = minf(velocity.length() / FULL_SPEED, 1.0) * MAX_LENGTH
	if not velocity.is_zero_approx():
		rotation = velocity.angle()
	queue_redraw()
