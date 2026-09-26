class_name PunchAbility
extends Ability

@export_group("Dependencies")
@export var punch_attack_scene: PackedScene

@export_group("Timing")
@export_range(0.01, 0.5, 0.01, "suffix:s") var attack_interval: float = 0.1
@export_range(0.01, 1.0, 0.01, "suffix:s") var hit_active_duration: float = 0.09

@export_group("Hit")
@export_range(0.0, 1000.0, 0.1) var damage: float = 20.0
@export_range(0.0, 2000.0, 10.0, "suffix:unit/s") var knockback: float = 800.0

@export_group("Hitbox")
@export_range(0.0, 100.0, 1.0, "suffix:unit") var side_offset: float = 14.0
@export_range(0.0, 150.0, 1.0, "suffix:unit") var hitbox_forward_offset: float = 46.0
@export_range(1.0, 100.0, 1.0, "suffix:unit") var hitbox_radius: float = 18.0
@export_range(1.0, 150.0, 1.0, "suffix:unit") var hitbox_height: float = 72.0

@export_group("Visual")
@export_range(0.0, 150.0, 1.0, "suffix:unit") var visual_start_distance: float = 30.0
@export_range(0.0, 150.0, 1.0, "suffix:unit") var visual_end_distance: float = 56.0
@export_range(0.01, 1.0, 0.01, "suffix:s") var move_duration: float = 0.10
@export_range(0.01, 1.0, 0.01, "suffix:s") var fade_duration: float = 0.05

@export_group("Feedback")
@export var hit_camera_shake: OneShotCameraShakeCue
@export var hit_sound: SoundCue

var _next_side_sign: float = -1.0
var _cooldown: float = 0.0


func _ready() -> void:
	assert(punch_attack_scene != null, "punch_attack_scene is required.")
	set_process(false)


func update(delta: float, _aim_direction: Vector2) -> void:
	_cooldown = maxf(_cooldown - maxf(delta, 0.0), 0.0)


func can_activate() -> bool:
	return _cooldown <= 0.0


func input_pressed(aim_direction: Vector2) -> void:
	_try_punch(aim_direction)


func input_held(_delta: float, aim_direction: Vector2) -> void:
	_try_punch(aim_direction)


func _try_punch(aim_direction: Vector2) -> void:
	if not can_activate():
		return

	var instance := punch_attack_scene.instantiate()
	var punch_attack := instance as PunchAttack
	if punch_attack == null:
		push_error("punch_attack_scene must be a PackedScene with a PunchAttack root node.")
		instance.queue_free()
		return

	punch_attack.damage = damage
	punch_attack.knockback = knockback
	punch_attack.hit_active_duration = hit_active_duration
	punch_attack.hit_camera_shake = hit_camera_shake
	punch_attack.hit_sound = hit_sound
	punch_attack.side_offset = side_offset
	punch_attack.hitbox_forward_offset = hitbox_forward_offset
	punch_attack.hitbox_radius = hitbox_radius
	punch_attack.hitbox_height = hitbox_height
	punch_attack.visual_start_distance = visual_start_distance
	punch_attack.visual_end_distance = visual_end_distance
	punch_attack.move_duration = move_duration
	punch_attack.fade_duration = fade_duration
	_ability_origin.add_child(punch_attack)
	punch_attack.launch(_ability_user, aim_direction, _next_side_sign, _feedback)
	_next_side_sign *= -1.0
	_cooldown = attack_interval
