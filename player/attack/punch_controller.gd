class_name PunchController
extends Node

signal camera_shake_requested(trauma: float)
signal sound_requested(request: SoundRequest)

@export var punch_attack_scene: PackedScene
@export_range(0.01, 2.0, 0.01, "suffix:s") var attack_interval: float = 0.20

var _last_aim_direction: Vector2 = Vector2.RIGHT
var _next_side_sign: float = -1.0
var _cooldown: float = 0.0
var _attacker: Node
var _input: PlayerInput
var _attack_root: Node2D


func _ready() -> void:
	assert(punch_attack_scene != null, "punch_attack_scene is required.")
	set_process(false)


func _process(delta: float) -> void:
	if not _input.is_attack_pressed:
		_cooldown = 0.0
		return

	_cooldown -= maxf(delta, 0.0)
	if _cooldown > 0.0:
		return

	_spawn_punch()
	_cooldown = attack_interval


## Called by the Player root after its children are ready.
func setup(attacker: Node, player_input: PlayerInput, attack_root: Node2D) -> void:
	_attacker = attacker
	_input = player_input
	_attack_root = attack_root
	set_process(true)


func _on_punch_camera_shake_requested(trauma: float) -> void:
	camera_shake_requested.emit(trauma)


func _on_punch_sound_requested(request: SoundRequest) -> void:
	sound_requested.emit(request)


func _spawn_punch() -> void:
	var instance := punch_attack_scene.instantiate()
	var punch_attack := instance as PunchAttack
	if punch_attack == null:
		push_error("punch_attack_scene must be a PackedScene with a PunchAttack root node.")
		instance.queue_free()
		return

	punch_attack.camera_shake_requested.connect(_on_punch_camera_shake_requested)
	punch_attack.sound_requested.connect(_on_punch_sound_requested)
	_update_aim_direction()
	_attack_root.add_child(punch_attack)
	punch_attack.launch(_attacker, _last_aim_direction, _next_side_sign)
	_next_side_sign *= -1.0


func _update_aim_direction() -> void:
	var aim_offset := _input.get_aim_offset(_attack_root)
	if not aim_offset.is_zero_approx():
		_last_aim_direction = aim_offset.normalized()
