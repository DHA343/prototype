class_name Main
extends Node2D

var _feedback: Feedback = Feedback.new()

@onready var player: Player = $Actors/Player
@onready var enemies: Node2D = $Actors/Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var damage_number_spawner: DamageNumberSpawner = $WorldUILayer/DamageNumberSpawner
@onready var world_sound_output: WorldSoundOutput = $WorldSoundOutput
@onready var camera_shake: CameraShake = $Camera2D/CameraShake
@onready var world_ui_layer: CanvasLayer = $WorldUILayer


func _ready() -> void:
	world_ui_layer.layer = RenderLayers.WORLD_UI
	crowd_manager.register_member(player, player.crowd)
	_feedback.sound_requested.connect(world_sound_output.request)
	_feedback.camera_shake_requested.connect(camera_shake.request)
	player.setup(_feedback)
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
