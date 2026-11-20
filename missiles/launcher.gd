class_name MissileLauncher
extends Node2D

@export_group("Firing")
@export var missile_scene: PackedScene
@export_range(0, 9, 1) var volley_size: int = 3
## 上向きを0度として、発射方向の中心を指定する。
@export_range(-180.0, 180.0, 1.0, "suffix:°") var launch_angle: float = 0.0
@export_range(0.0, 180.0, 1.0, "suffix:°") var spread: float = 45.0
@export_range(0.0, 0.5, 0.01, "suffix:s") var shot_interval: float = 0.12
@export_range(0.0, 2400.0, 10.0, "suffix:px/s") var minimum_launch_speed: float = 240.0
@export_range(0.0, 2400.0, 10.0, "suffix:px/s") var maximum_launch_speed: float = 480.0

var _pending_shots: Array[Dictionary] = []
var _flights: Array[Projectile] = []
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func fire() -> void:
	_queue_volley()


func fire_from(point: Vector2) -> void:
	_queue_volley(point)


func advance(delta: float, enemies: Array[Enemy]) -> void:
	for index in range(_pending_shots.size() - 1, -1, -1):
		var shot: Dictionary = _pending_shots[index]
		shot.delay -= delta
		if shot.delay <= 0.000001:
			_launch(shot)
			_pending_shots.remove_at(index)

	for index in range(_flights.size() - 1, -1, -1):
		var projectile := _flights[index]
		projectile.advance(delta, enemies)
		if not projectile.active:
			_flights.remove_at(index)


func _queue_volley(origin: Variant = null) -> void:
	for index in volley_size:
		_pending_shots.append({
			"delay": index * shot_interval,
			"origin": origin,
			"heading": deg_to_rad(launch_angle + _random.randf_range(-spread, spread)),
			"seed": _random.randf_range(0.0, TAU),
			"speed": _random.randf_range(
				minf(minimum_launch_speed, maximum_launch_speed),
				maxf(minimum_launch_speed, maximum_launch_speed),
			),
		})


func _launch(shot: Dictionary) -> void:
	var projectile := missile_scene.instantiate() as Projectile
	assert(projectile != null, "Projectile scene must have a Projectile root.")
	add_child(projectile)
	var direction := Vector2.UP.rotated(shot.heading)
	var origin: Vector2 = global_position if shot.origin == null else shot.origin
	projectile.spawn(to_local(origin), direction * float(shot.speed), shot.seed)
	_flights.append(projectile)
