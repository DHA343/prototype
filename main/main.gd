class_name Main
extends Node2D

@onready var player: Player = $Actors/Player
@onready var enemies: Node2D = $Actors/Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var damage_number_spawner: DamageNumberSpawner = $WorldUILayer/DamageNumberSpawner
@onready var world_sound_output: WorldSoundOutput = $WorldSoundOutput
@onready var impact_camera_shake: ImpactCameraShake = $Camera2D/CameraShake/ImpactCameraShake
@onready var world_ui_layer: CanvasLayer = $WorldUILayer


func _ready() -> void:
	world_ui_layer.layer = RenderLayers.WORLD_UI
	crowd_manager.register_member(player, player.crowd)
	player.sound_requested.connect(world_sound_output.request)
	player.camera_shake_requested.connect(impact_camera_shake.request_trauma)
	enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
	enemy_spawner.setup(player, enemies, spawn_area)
	enemy_spawner.start()


func _on_enemy_spawned(enemy: Enemy) -> void:
	crowd_manager.register_member(enemy, enemy.crowd)
	enemy.damaged.connect(_on_enemy_damaged)


func _on_enemy_damaged(
	requested_damage: float,
	hit_position: Vector2,
	resulting_knockback_velocity: Vector2
) -> void:
	damage_number_spawner.spawn(requested_damage, resulting_knockback_velocity, hit_position)
