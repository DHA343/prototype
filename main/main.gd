class_name Main
extends Node2D

var _feedback: Feedback = Feedback.new()

@onready var orb: Orb = $Actors/Orb
@onready var enemies: Node2D = $Actors/Enemies
@onready var crowd_manager: CrowdManager = $CrowdManager
@onready var spawn_area: SpawnArea = $SpawnArea
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var damage_number_spawner: DamageNumberSpawner = $WorldUILayer/DamageNumberSpawner
@onready var world_sound_output: WorldSoundOutput = $WorldSoundOutput
@onready var camera: GameCamera = $Camera2D
@onready var camera_shake: CameraShake = $Camera2D/CameraShake
@onready var world_ui_layer: CanvasLayer = $WorldUILayer


func _ready() -> void:
	world_ui_layer.layer = RenderLayers.WORLD_UI
	_feedback.sound_requested.connect(world_sound_output.request)
	_feedback.camera_shake_requested.connect(camera_shake.request)
	orb.setup(_feedback)
	camera.setup_follow(orb)
	enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
	enemy_spawner.setup(enemies, spawn_area)
	enemy_spawner.start()


func _on_enemy_spawned(enemy: Enemy) -> void:
	crowd_manager.register_member(enemy, enemy.crowd)
	enemy.damaged.connect(_on_enemy_damaged)
	enemy.sound_requested.connect(_feedback.sound_requested.emit)


func _on_enemy_damaged(
	requested_damage: float,
	hit_position: Vector2,
	resulting_knockback_velocity: Vector2
) -> void:
	damage_number_spawner.spawn(requested_damage, resulting_knockback_velocity, hit_position)
