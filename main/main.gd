class_name Main
extends Node2D

@onready var player: Player = $Player
@onready var enemies: Node2D = $Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	enemy_spawner.setup(player, crowd_manager, enemies, spawn_area)
	enemy_spawner.start()
