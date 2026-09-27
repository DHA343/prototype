class_name SpawnArea
extends Area2D

## Insets both the spawn range and the wandering territory from the rectangle's edges.
@export_range(0.0, 500.0, 1.0, "suffix:px") var margin: float = 0.0

var bounds: Rect2:
	get:
		var size := _rectangle.size
		var inset := (Vector2.ONE * margin).min(size * 0.5)
		return Rect2(_collision_shape.global_position - size * 0.5 + inset, size - inset * 2.0)

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D


func _ready() -> void:
	monitoring = false
	monitorable = false
	assert(_rectangle != null, "CollisionShape2D must use a RectangleShape2D shape.")


func random_point() -> Vector2:
	var area := bounds
	return Vector2(
		randf_range(area.position.x, area.end.x),
		randf_range(area.position.y, area.end.y)
	)
