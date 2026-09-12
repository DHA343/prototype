class_name SpawnArea
extends Area2D

var bounds: Rect2:
	get:
		var size := _rectangle.size
		return Rect2(_collision_shape.global_position - size * 0.5, size)

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
