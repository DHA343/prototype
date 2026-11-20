extends Node2D

@export var lab: PinballLab

var _shot_velocity: Vector2 = Vector2.ZERO


func _physics_process(_delta: float) -> void:
	_shot_velocity = lab.predict_shot()
	queue_redraw()


func _draw() -> void:
	if _shot_velocity == Vector2.ZERO:
		return
	var start := to_local(lab.ball.global_position)
	var end := to_local(lab.ball.global_position + _shot_velocity.normalized() * 270.0)
	draw_line(start, end, Color(0.6, 0.8, 0.85), 3.0)
