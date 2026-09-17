class_name DamageNumber
extends Node2D

@export_group("Motion")
@export_range(0.0, 1.0, 0.01) var distance_per_impulse: float = 0.18
@export_range(0.0, 500.0, 10.0, "suffix:px") var max_distance: float = 250.0
@export_range(0.0, 90.0, 1.0, "suffix:deg") var direction_variation: float = 20.0
@export_range(0.0, 1.0, 0.01) var distance_variation: float = 0.2

@export_group("Bounce")
@export_range(0.0, 200.0, 1.0, "suffix:px") var bounce_height: float = 70.0
@export_range(0.0, 1.0, 0.01) var bounce_height_variation: float = 0.25
@export_range(100.0, 10000.0, 100.0, "suffix:px/s²") var gravity: float = 5000.0
@export_range(0.0, 1.0, 0.01) var restitution: float = 0.6

@export_group("Lifetime")
@export_range(0.1, 2.0, 0.01, "suffix:s") var lifetime: float = 0.7
@export_range(0.0, 1.0, 0.01) var lifetime_variation: float = 0.2
@export_range(0.01, 1.0, 0.01, "suffix:s") var fade_time: float = 0.15

var _origin: Vector2 = Vector2.ZERO
var _direction: Vector2 = Vector2.ZERO
var _distance: float = 0.0
var _height: float = 0.0
var _height_speed: float = 0.0
var _elapsed: float = 0.0
var _lifetime: float = 0.7

@onready var _label: Label = $Label


func _ready() -> void:
	set_process(false)


func launch(damage: float, knockback_velocity: Vector2) -> void:
	_label.text = str(roundi(damage))
	_lifetime = maxf(lifetime * _variation(lifetime_variation), 0.01)
	_origin = global_position
	_elapsed = 0.0
	_height = 0.0
	modulate.a = 1.0

	var knockback_length := knockback_velocity.length()
	if is_zero_approx(knockback_length):
		_direction = Vector2.ZERO
		_distance = 0.0
	else:
		_direction = knockback_velocity.normalized().rotated(_random_angle())
		var distance := (
			knockback_length
			* distance_per_impulse
			* _variation(distance_variation)
		)
		_distance = minf(distance, max_distance)

	var varied_bounce_height := bounce_height * _variation(bounce_height_variation)
	_height_speed = sqrt(2.0 * gravity * varied_bounce_height)
	global_position = _origin
	set_process(true)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= _lifetime:
		queue_free()
		return

	_height_speed -= gravity * delta
	_height += _height_speed * delta
	if _height < 0.0:
		_height = 0.0
		_height_speed = -_height_speed * restitution

	var progress := clampf(_elapsed / _lifetime, 0.0, 1.0)
	var horizontal := _direction * _distance * (1.0 - pow(1.0 - progress, 2.0))
	global_position = _origin + horizontal + Vector2(0.0, -_height)

	if fade_time > 0.0:
		modulate.a = clampf((_lifetime - _elapsed) / fade_time, 0.0, 1.0)
	else:
		modulate.a = 1.0


func _variation(amount: float) -> float:
	return randf_range(1.0 - amount, 1.0 + amount)


func _random_angle() -> float:
	return deg_to_rad(randf_range(-direction_variation, direction_variation))
