@tool
class_name SpawnArea
extends Node2D

## The rectangle is authored independently of the playfield. Coordinates describe its center.
@export var size: Vector2 = Vector2(600.0, 96.0):
	set(value):
		size = value.max(Vector2.ZERO)
		queue_redraw()


func _draw() -> void:
	if Engine.is_editor_hint():
		var rectangle := Rect2(-size * 0.5, size)
		draw_rect(rectangle, Color(0.25, 0.7, 0.45, 0.08))
		draw_rect(rectangle, Color(0.25, 0.7, 0.45, 0.7), false, 3.0)


func fits(radius: float) -> bool:
	return minf(size.x, size.y) >= radius * 2.0


func random_point(radius: float) -> Vector2:
	var half := size * 0.5 - Vector2.ONE * radius
	return to_global(Vector2(randf_range(-half.x, half.x), randf_range(-half.y, half.y)))
