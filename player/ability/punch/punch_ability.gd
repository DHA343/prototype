class_name PunchAbility
extends Ability

@export var punch_attack_scene: PackedScene
@export_range(0.01, 0.5, 0.01, "suffix:s") var attack_interval: float = 0.1

var _next_side_sign: float = -1.0
var _cooldown: float = 0.0


func _ready() -> void:
	assert(punch_attack_scene != null, "punch_attack_scene is required.")
	set_process(false)


func update(delta: float) -> void:
	_cooldown = maxf(_cooldown - maxf(delta, 0.0), 0.0)


func can_activate() -> bool:
	return _cooldown <= 0.0


func input_pressed(aim_direction: Vector2) -> void:
	_try_punch(aim_direction)


func input_held(_delta: float, aim_direction: Vector2) -> void:
	_try_punch(aim_direction)


func _on_punch_camera_shake_requested(request: CameraShakeRequest) -> void:
	camera_shake_requested.emit(request)


func _on_punch_sound_requested(request: SoundRequest) -> void:
	sound_requested.emit(request)


func _try_punch(aim_direction: Vector2) -> void:
	if not can_activate():
		return

	var instance := punch_attack_scene.instantiate()
	var punch_attack := instance as PunchAttack
	if punch_attack == null:
		push_error("punch_attack_scene must be a PackedScene with a PunchAttack root node.")
		instance.queue_free()
		return

	punch_attack.camera_shake_requested.connect(_on_punch_camera_shake_requested)
	punch_attack.sound_requested.connect(_on_punch_sound_requested)
	_attack_root.add_child(punch_attack)
	punch_attack.launch(_ability_user, aim_direction, _next_side_sign)
	_next_side_sign *= -1.0
	_cooldown = attack_interval
