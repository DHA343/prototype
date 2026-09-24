class_name SlamAbility
extends Ability

enum Phase {
	IDLE,
	CHARGING,
	WINDUP,
}

const MAX_CHARGE_STAGE: int = 3

@export var slam_attack_scene: PackedScene
@export var hammer_visual_scene: PackedScene

@export_group("Charge")
@export_range(0.01, 3.0, 0.01, "suffix:s") var first_charge_time: float = 0.5
@export_range(0.01, 3.0, 0.01, "suffix:s") var charge_step_time: float = 0.5
@export_range(0.1, 1.0, 0.01) var charge_movement_multiplier: float = 0.5

@export_group("Slam")
@export_range(0.0, 500.0, 1.0, "suffix:unit") var slam_distance: float = 50.0
@export_range(0.01, 1.0, 0.01, "suffix:s") var windup_duration: float = 0.1
@export_range(0.01, 1.0, 0.01, "suffix:s") var expand_duration: float = 0.2
@export_range(1.0, 500.0, 1.0, "suffix:unit") var base_radius: float = 55.0
@export_range(0.0, 500.0, 1.0, "suffix:unit") var radius_per_stage: float = 30.0
@export_range(0.0, 1000.0, 0.1) var base_damage: float = 10.0
@export_range(0.0, 1000.0, 0.1) var damage_per_stage: float = 8.0
@export_range(0.0, 2000.0, 10.0, "suffix:unit/s") var base_knockback: float = 300.0
@export_range(0.0, 2000.0, 10.0, "suffix:unit/s") var knockback_per_stage: float = 100.0

@export_group("Audio")
@export var charge_sound: SoundCue
@export var charge_stage_sound: SoundCue

var _phase: Phase = Phase.IDLE
var _charge_time: float = 0.0
var _charge_stage: int = 0
var _windup_remaining: float = 0.0
var _slam_direction: Vector2 = Vector2.RIGHT
var _hammer_visual: HammerVisual


func _ready() -> void:
	assert(slam_attack_scene != null, "slam_attack_scene is required.")
	assert(hammer_visual_scene != null, "hammer_visual_scene is required.")
	set_process(false)


func _exit_tree() -> void:
	if is_instance_valid(_hammer_visual):
		_hammer_visual.queue_free()


func update(delta: float, aim_direction: Vector2) -> void:
	if _phase != Phase.WINDUP:
		return
	_hammer_visual.set_aim_direction(aim_direction)
	_windup_remaining -= maxf(delta, 0.0)
	if _windup_remaining <= 0.0:
		_launch_slam(aim_direction)


func can_activate() -> bool:
	return _phase == Phase.IDLE


func blocks_other_abilities() -> bool:
	return _phase != Phase.IDLE


func get_movement_multiplier() -> float:
	return charge_movement_multiplier if _phase != Phase.IDLE else 1.0


func input_pressed(aim_direction: Vector2) -> void:
	if not can_activate():
		return
	var instance := hammer_visual_scene.instantiate()
	_hammer_visual = instance as HammerVisual
	if _hammer_visual == null:
		push_error("hammer_visual_scene must have a HammerVisual root node.")
		instance.queue_free()
		return

	_attack_root.add_child(_hammer_visual)
	_hammer_visual.begin_charge(aim_direction, charge_sound)
	_charge_time = 0.0
	_charge_stage = 0
	_phase = Phase.CHARGING


func input_held(delta: float, aim_direction: Vector2) -> void:
	if _phase != Phase.CHARGING:
		return
	_hammer_visual.set_aim_direction(aim_direction)
	_charge_time += maxf(delta, 0.0)
	var next_stage := _get_charge_stage(_charge_time)
	while _charge_stage < next_stage:
		_charge_stage += 1
		if charge_stage_sound != null:
			_feedback.sound_requested.emit(SoundRequest.new(charge_stage_sound, _attack_root.global_position, self))


func input_released(aim_direction: Vector2) -> void:
	if _phase != Phase.CHARGING:
		return
	_slam_direction = aim_direction.normalized()
	if _slam_direction.is_zero_approx():
		_slam_direction = Vector2.RIGHT
	_windup_remaining = windup_duration
	_phase = Phase.WINDUP
	_hammer_visual.begin_windup(_slam_direction, windup_duration)


func _get_charge_stage(elapsed: float) -> int:
	if elapsed < first_charge_time:
		return 0
	return mini(1 + int((elapsed - first_charge_time) / charge_step_time), MAX_CHARGE_STAGE)


func _launch_slam(aim_direction: Vector2) -> void:
	if not aim_direction.is_zero_approx():
		_slam_direction = aim_direction.normalized()
	var slam_position := _attack_root.global_position + _slam_direction * slam_distance
	var instance := slam_attack_scene.instantiate()
	var slam_attack := instance as SlamAttack
	if slam_attack == null:
		push_error("slam_attack_scene must have a SlamAttack root node.")
		instance.queue_free()
		_phase = Phase.IDLE
		return

	get_tree().current_scene.add_child(slam_attack)
	slam_attack.global_position = slam_position
	slam_attack.launch(
		_ability_user,
		_slam_direction,
		base_radius + radius_per_stage * _charge_stage,
		base_damage + damage_per_stage * _charge_stage,
		base_knockback + knockback_per_stage * _charge_stage,
		expand_duration,
		_feedback
	)
	if is_instance_valid(_hammer_visual):
		_hammer_visual.impact()
	_hammer_visual = null
	_phase = Phase.IDLE
