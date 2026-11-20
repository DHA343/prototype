class_name EnemySpawner
extends Node

signal enemy_spawned(enemy: Enemy)
signal spawn_skipped

const MAX_ATTEMPTS: int = 16

@export var enabled: bool = true
@export_range(0.1, 30.0, 0.1, "suffix:s") var interval: float = 1.0
@export var enemy_scene: PackedScene
@export var spawn_area: SpawnArea
@export var spawn_parent: Node2D

var enemy_radius: float = 30.0
var _elapsed: float = 0.0
var _can_spawn: Callable


func setup(can_spawn: Callable) -> void:
	_can_spawn = can_spawn
	var template := enemy_scene.instantiate() as Enemy
	assert(template != null, "Enemy scene must have an Enemy root.")
	enemy_radius = template.radius
	template.free()


func advance(delta: float) -> void:
	if not enabled:
		return
	_elapsed += delta
	while _elapsed + 0.000001 >= interval:
		_elapsed = maxf(0.0, _elapsed - interval)
		_spawn_one()


func _spawn_one() -> void:
	var enemy := enemy_scene.instantiate() as Enemy
	if spawn_area.fits(enemy.radius):
		for _attempt in MAX_ATTEMPTS:
			var point := spawn_area.random_point(enemy.radius)
			if not _can_spawn.call(point, enemy.radius):
				continue
			enemy.position = spawn_parent.to_local(point)
			spawn_parent.add_child(enemy)
			enemy_spawned.emit(enemy)
			return
	enemy.free()
	spawn_skipped.emit()
