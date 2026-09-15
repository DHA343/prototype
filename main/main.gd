class_name Main
extends Node2D

@onready var player: Player = $Actors/Player
@onready var enemies: Node2D = $Actors/Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner


func _ready() -> void:
	if player.crowd == null:
		push_error("Player crowd settings are not assigned.")
	else:
		crowd_manager.register_member(
			player,
			player.crowd.radius,
			player.crowd.avoidance_radius,
			player.crowd.response
		)

	enemy_spawner.setup(player, crowd_manager, enemies, spawn_area)
	enemy_spawner.start()
