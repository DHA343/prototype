@tool
class_name PinballBumper
extends StaticBody2D

signal hit_occurred(point: Vector2)

@export_range(18.0, 96.0, 3.0, "suffix:px") var radius: float = 54.0:
	set(value):
		radius = value
		_refresh_shape()
@export_range(300.0, 2700.0, 30.0, "suffix:px/s") var exit_speed: float = 1380.0
@export var color: Color = Color(0.48, 0.53, 0.57):
	set(value):
		color = value
		queue_redraw()
@export var hit_sound: SoundCue

@export_group("Hit Animation")
@export_range(1.0, 1.5, 0.01) var hit_scale: float = 1.2
@export_range(0.01, 0.2, 0.01, "suffix:s") var expand_duration: float = 0.05
@export_range(0.01, 0.5, 0.01, "suffix:s") var return_duration: float = 0.15

var _visual_scale: float = 1.0
var _hit_tween: Tween

@onready var _collision: CollisionShape2D = $CollisionShape2D


func _ready() -> void:
	_refresh_shape()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius * _visual_scale, color)


func hit(point: Vector2) -> void:
	if _hit_tween != null:
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_method(
		_set_visual_scale, _visual_scale, hit_scale, expand_duration
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_hit_tween.tween_method(
		_set_visual_scale, hit_scale, 1.0, return_duration
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hit_occurred.emit(point)


func _set_visual_scale(value: float) -> void:
	_visual_scale = value
	queue_redraw()


func _refresh_shape() -> void:
	queue_redraw()
	if not is_node_ready():
		return
	var shape := CircleShape2D.new()
	shape.radius = radius
	_collision.shape = shape
