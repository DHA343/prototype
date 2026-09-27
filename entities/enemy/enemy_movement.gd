class_name EnemyMovement
extends Node

@export_group("Wander")
@export_range(0.0, 500.0, 10.0, "suffix:px/s") var wander_speed: float = 80.0
@export_range(0.0, 5000.0, 10.0, "suffix:px/s²") var wander_acceleration: float = 120.0
@export_range(0.0, 16.0, 0.1, "suffix:rad/s") var max_turn_rate: float = 5.0
@export_range(0.0, 16.0, 0.1) var noise_frequency: float = 1.0

@export_group("Chase")
@export_range(0.0, 500.0, 10.0, "suffix:px/s") var chase_speed: float = 160.0
@export_range(0.0, 5000.0, 10.0, "suffix:px/s²") var chase_acceleration: float = 200.0

@export_group("Bounds")
@export_range(0.0, 500.0, 10.0, "suffix:px") var boundary_margin: float = 60.0

var territory: SpawnArea = null
var target: Node2D = null

var velocity: Vector2:
	get: return _velocity

var _velocity: Vector2 = Vector2.ZERO
var _heading: float = 0.0
var _elapsed_time: float = 0.0
var _noise: FastNoiseLite = FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = noise_frequency
	_noise.fractal_octaves = 3
	_heading = randf_range(0.0, TAU)


func update(delta: float, global_position: Vector2) -> void:
	_elapsed_time += delta

	var desired_velocity: Vector2
	var acceleration: float

	if is_instance_valid(target):
		desired_velocity = _chase_direction(global_position) * chase_speed
		acceleration = chase_acceleration
	else:
		desired_velocity = _wander_direction(delta, global_position) * wander_speed
		acceleration = wander_acceleration

	if not desired_velocity.is_zero_approx():
		_heading = desired_velocity.angle()

	_velocity = _velocity.move_toward(desired_velocity, acceleration * delta)


func clear() -> void:
	_velocity = Vector2.ZERO


# --- 方向の決定 ---

func _wander_direction(delta: float, global_position: Vector2) -> Vector2:
	var turn := _noise.get_noise_1d(_elapsed_time) * max_turn_rate * delta
	var direction := Vector2.from_angle(_heading + turn)
	return _steer_inward(direction, global_position)


func _chase_direction(global_position: Vector2) -> Vector2:
	var to_target := target.global_position - global_position
	if to_target.is_zero_approx():
		return Vector2.ZERO
	return to_target.normalized()


# --- 境界処理 ---

func _steer_inward(direction: Vector2, global_position: Vector2) -> Vector2:
	if territory == null or boundary_margin <= 0.0:
		return direction

	var inner := territory.bounds.grow(-boundary_margin)
	var inward := Vector2(
		_axis_overshoot(global_position.x, inner.position.x, inner.end.x, boundary_margin),
		_axis_overshoot(global_position.y, inner.position.y, inner.end.y, boundary_margin)
	)
	if inward.is_zero_approx():
		return direction

	return direction.slerp(inward.normalized(), minf(inward.length(), 1.0))


static func _axis_overshoot(value: float, minimum: float, maximum: float, margin: float) -> float:
	if value < minimum:
		return (minimum - value) / margin
	if value > maximum:
		return -(value - maximum) / margin
	return 0.0
