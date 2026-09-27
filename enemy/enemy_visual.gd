class_name EnemyVisual
extends Node2D

@export_range(1.0, 500.0, 1.0, "suffix:px") var radius: float = 40.0
@export var full_health_color: Color = Color(0.2, 0.7, 1.0, 1.0)
@export var low_health_color: Color = Color(1.0, 0.3, 0.3, 1.0)

var _health_ratio: float = 1.0


func _draw() -> void:
	var damage_ratio := 1.0 - _health_ratio
	var color := full_health_color.lerp(low_health_color, damage_ratio)
	draw_circle(Vector2.ZERO, radius, color)


func update_health(current_health: float, max_health: float) -> void:
	if max_health <= 0.0:
		_health_ratio = 0.0
	else:
		_health_ratio = clampf(current_health / max_health, 0.0, 1.0)

	queue_redraw()


func set_scale_multiplier(value: float) -> void:
	scale = Vector2.ONE * value
