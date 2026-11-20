@tool
extends Projectile

@export_group("Flight")
@export_range(0.1, 40.0, 0.1, "suffix:1/s") var turn_response: float = 19.0
@export_range(0.0, 300.0, 1.0, "suffix:px/s²") var acceleration: float = 81.0
@export_range(100.0, 1200.0, 10.0, "suffix:px") var search_radius: float = 500.0
@export_range(0.01, 0.5, 0.001, "suffix:s") var search_interval: float = 0.1
@export_range(0.0, 1.0, 0.01, "suffix:s") var rehit_delay: float = 0.1

var _hit_ready_at: Dictionary[int, float] = {}
var _search_at: float = 0.0


func spawn(origin: Vector2, initial_velocity: Vector2, seed_value: float) -> void:
	_hit_ready_at.clear()
	_search_at = 0.0
	super.spawn(origin, initial_velocity, seed_value)


func _move(delta: float) -> void:
	var target := get_target()
	if target != null and (target.collision_layer == 0 or not _can_hit_enemy(target)
		or global_position.distance_squared_to(target.global_position) >= search_radius * search_radius):
		target = null
	if target == null and _age >= _search_at:
		target = _find_target(search_radius)
		if target == null:
			_search_at = _age + search_interval
	_target = target
	state = State.HOMING if target != null else State.STRAIGHT
	var turn := 0.0
	if target != null:
		var direction := position.direction_to(_get_target_position())
		turn = _velocity.angle_to(direction) * (1.0 - exp(-turn_response * delta))
	_velocity = _velocity.rotated(turn) + _velocity.normalized() * (acceleration * delta)
	position += _velocity * delta


func _can_hit_enemy(enemy: Enemy) -> bool:
	return _age >= _hit_ready_at.get(enemy.get_instance_id(), 0.0)


func _on_penetration(enemy: Enemy) -> void:
	_hit_ready_at[enemy.get_instance_id()] = _age + rehit_delay
