class_name Main
extends Node2D

@onready var player: Player = $Actors/Player
@onready var enemies: Node2D = $Actors/Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var damage_number_spawner: DamageNumberSpawner = $DamageNumberLayer/DamageNumberSpawner
@onready var world_sound_output: WorldSoundOutput = $WorldSoundOutput
@onready var punch_controller: PunchController = $Actors/Player/PunchController


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

	punch_controller.setup(world_sound_output)
	enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
	enemy_spawner.setup(player, crowd_manager, enemies, spawn_area)
	enemy_spawner.start()


func _on_enemy_spawned(enemy: Enemy) -> void:
	enemy.damaged.connect(_on_enemy_damaged)


func _on_enemy_damaged(
	damage: float,
	hit_position: Vector2,
	knockback_velocity: Vector2
) -> void:
	damage_number_spawner.spawn(damage, knockback_velocity, hit_position)
