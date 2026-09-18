class_name Knockback
extends Node

@export_range(0.0, 10000.0, 10.0, "suffix:unit/s") var max_speed: float = 1200.0
@export_range(0.01, 5.0, 0.01, "suffix:s") var duration: float = 0.24
@export var transition_type: Tween.TransitionType = Tween.TRANS_QUAD
@export var ease_type: Tween.EaseType = Tween.EASE_OUT

var velocity: Vector2:
	get:
		return _initial_velocity * _decay_ratio()

var _initial_velocity: Vector2 = Vector2.ZERO
var _elapsed_time: float = 0.0


func apply_hit(hit: HitData, resistance: float) -> void:
	var direction := hit.hit_direction.normalized()
	apply(direction * hit.knockback * (1.0 - resistance))


func apply(new_velocity: Vector2) -> void:
	_initial_velocity = (velocity + new_velocity).limit_length(maxf(max_speed, 0.0))
	_elapsed_time = 0.0


func update(delta: float) -> void:
	if _initial_velocity.is_zero_approx():
		return

	_elapsed_time += maxf(delta, 0.0)
	if _elapsed_time >= duration:
		clear()


func clear() -> void:
	_initial_velocity = Vector2.ZERO
	_elapsed_time = 0.0


func _decay_ratio() -> float:
	if _initial_velocity.is_zero_approx():
		return 0.0

	return clampf(
		Tween.interpolate_value(
			1.0,
			-1.0,
			_elapsed_time,
			maxf(duration, 0.01),
			transition_type,
			ease_type
		),
		0.0,
		1.0
	)
