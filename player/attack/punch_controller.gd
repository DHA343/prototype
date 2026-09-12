class_name PunchController
extends Node

@export var punch_attack_scene: PackedScene
@export_range(0.01, 2.0, 0.01, "suffix:s") var attack_interval: float = 0.20

var _last_aim_direction: Vector2 = Vector2.RIGHT
var _next_side_sign: float = -1.0
var _cooldown: float = 0.0

@onready var _player: Player = get_parent() as Player
@onready var _attack_root: Node2D = $"../AttackRoot"


func _ready() -> void:
	assert(_player != null, "PunchController: Playerの子として配置する必要があります")
	assert(_attack_root != null, "PunchController: AttackRootが必要です")
	assert(punch_attack_scene != null, "PunchController: punch_attack_sceneが必要です")


func _process(delta: float) -> void:
	if not Input.is_action_pressed("attack"):
		_cooldown = 0.0
		return

	_cooldown -= maxf(delta, 0.0)
	if _cooldown > 0.0:
		return

	_spawn_punch()
	_cooldown = attack_interval


func _spawn_punch() -> void:
	var instance := punch_attack_scene.instantiate()
	var punch_attack := instance as PunchAttack
	if punch_attack == null:
		push_error("PunchController: punch_attack_sceneはPunchAttackをrootに持つPackedSceneである必要があります")
		instance.queue_free()
		return

	_update_aim_direction()
	punch_attack.setup(_player, _last_aim_direction, _next_side_sign)
	_attack_root.add_child(punch_attack)
	_next_side_sign *= -1.0


func _update_aim_direction() -> void:
	var aim_offset := _player.get_global_mouse_position() - _player.global_position
	if not aim_offset.is_zero_approx():
		_last_aim_direction = aim_offset.normalized()
