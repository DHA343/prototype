class_name EnemySpawner
extends Node

signal enemy_spawned(enemy: Enemy)

@export var enemy_scene: PackedScene

@export_group("Population")
@export_range(0, 1000, 1) var target_count: int = 30
@export_range(0.0, 10.0, 0.1, "suffix:s") var respawn_delay: float = 0.5

var _target: Node2D = null
var _spawn_parent: Node = null
var _spawn_area: SpawnArea = null
var _is_started: bool = false
var _alive_count: int = 0


func setup(target: Node2D, spawn_parent: Node, spawn_area: SpawnArea) -> void:
	_target = target
	_spawn_parent = spawn_parent
	_spawn_area = spawn_area


func start() -> void:
	if _is_started:
		return
	if not _has_valid_setup():
		return

	_is_started = true
	for _enemy_index in target_count:
		if _spawn_enemy() == null:
			return


func _spawn_enemy() -> Enemy:
	var instance := enemy_scene.instantiate()
	var enemy := instance as Enemy
	if enemy == null:
		push_error("enemy_scene must be a PackedScene with an Enemy root node.")
		instance.queue_free()
		return null

	_spawn_parent.add_child(enemy)
	enemy.global_position = _spawn_area.random_point()
	enemy.start(_target)
	enemy.died.connect(_on_enemy_died)

	_alive_count += 1
	enemy_spawned.emit(enemy)
	return enemy


func _on_enemy_died(_enemy: Enemy) -> void:
	_alive_count = maxi(_alive_count - 1, 0)
	get_tree().create_timer(maxf(respawn_delay, 0.0)).timeout.connect(_on_respawn_timer_timeout)


func _on_respawn_timer_timeout() -> void:
	if _alive_count >= target_count:
		return

	_spawn_enemy()


func _has_valid_setup() -> bool:
	if enemy_scene == null:
		push_error("enemy_scene is not assigned.")
		return false
	if not is_instance_valid(_target):
		push_error("target is not assigned.")
		return false
	if not is_instance_valid(_spawn_parent):
		push_error("spawn_parent is not assigned.")
		return false
	if not is_instance_valid(_spawn_area):
		push_error("spawn_area is not assigned.")
		return false

	return true
