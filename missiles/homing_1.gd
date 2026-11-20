@tool
extends Projectile

@export_group("Flight")
@export_range(0.0, 1.0, 0.01, "suffix:s") var tracking_delay: float = 0.5
@export_range(300.0, 5000.0, 10.0, "suffix:px/s") var tracking_speed: float = 3600.0
## 1秒あたりの速度補間の応答係数。
@export_range(0.1, 12.0, 0.1, "suffix:1/s") var tracking_response: float = 3.0
@export_range(0.0, 12.0, 0.1, "suffix:1/s") var launch_damping: float = 3.65
@export_range(0.01, 0.5, 0.01, "suffix:s") var search_interval: float = 0.1
@export_range(100.0, 1200.0, 10.0, "suffix:px") var search_radius: float = 800.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var rehit_delay: float = 0.5

@export_group("Departure")
@export_range(0.0, 0.4, 0.01, "suffix:s") var departure_time: float = 0.15
@export_range(0.0, 2400.0, 30.0, "suffix:px/s") var departure_speed: float = 1500.0
@export_range(0.0, 3000.0, 10.0, "suffix:px/s²") var departure_side_acceleration: float = 1800.0
@export_range(0.1, 12.0, 0.1, "suffix:1/s") var return_response: float = 3.2

var _hit_ready_at: Dictionary[int, float] = {}
var _search_at: float = 0.0
var _return_target: Enemy
var _departure_started_at: float = -1.0
var _departure_normal: Vector2 = Vector2.ZERO
var _departure_forward: Vector2 = Vector2.ZERO
var _departure_side: float = 1.0


func spawn(origin: Vector2, initial_velocity: Vector2, seed_value: float) -> void:
	_hit_ready_at.clear()
	_search_at = 0.0
	_return_target = null
	_departure_side = -1.0 if seed_value < PI else 1.0
	super.spawn(origin, initial_velocity, seed_value)


func _move(delta: float) -> void:
	if _age + 0.000001 < tracking_delay:
		_velocity *= exp(-launch_damping * delta)
		position += _velocity * delta
		return

	var target := get_target()
	if target == null or target.collision_layer == 0:
		target = null
		if _age >= _search_at:
			target = _find_target(search_radius)
			if target == null:
				_search_at = _age + search_interval
	_target = target
	if not is_instance_valid(_return_target) or _return_target != target:
		_return_target = null

	state = State.HOMING if target != null else State.STRAIGHT
	if target != null:
		var goal_velocity := position.direction_to(_get_target_position()) * tracking_speed
		if _return_target != null:
			_update_return_velocity(goal_velocity, delta)
		else:
			_velocity = _velocity.lerp(goal_velocity, 1.0 - exp(-tracking_response * delta))
	position += _velocity * delta


func _update_return_velocity(goal_velocity: Vector2, delta: float) -> void:
	var elapsed := _age - _departure_started_at
	if elapsed >= departure_time:
		_velocity = _velocity.lerp(goal_velocity, 1.0 - exp(-return_response * delta))
		return

	var recovery := smoothstep(0.0, departure_time, elapsed)
	var pulse := sin(PI * elapsed / departure_time)
	_velocity += _departure_normal * departure_side_acceleration * pulse * delta
	var response := return_response * lerpf(0.15, 1.0, recovery)
	_velocity = _velocity.lerp(goal_velocity, 1.0 - exp(-response * delta))

	var forward_speed := _velocity.dot(_departure_forward)
	var release := smoothstep(departure_time * 0.5, departure_time, elapsed)
	var departure_weight := (1.0 - exp(-36.0 * delta)) * (1.0 - release)
	_velocity += _departure_forward * ((departure_speed - forward_speed) * departure_weight)


func _can_hit_enemy(enemy: Enemy) -> bool:
	return _age >= _hit_ready_at.get(enemy.get_instance_id(), 0.0)


func _on_penetration(enemy: Enemy) -> void:
	_hit_ready_at[enemy.get_instance_id()] = _age + rehit_delay
	var next_target := _find_target(search_radius)
	if next_target != null:
		_target = next_target
		_return_target = null
	elif enemy == get_target() and state == State.HOMING:
		_return_target = enemy
		_departure_started_at = _age
		_departure_forward = _velocity.normalized()
		_departure_normal = _departure_forward.orthogonal() * _departure_side
		_departure_side *= -1.0
