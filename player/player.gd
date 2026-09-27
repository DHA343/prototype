class_name Player
extends Node2D

signal sound_requested(request: SoundRequest)
signal hit_landed(hit_position: Vector2, impact_speed: float)
signal charge_started
signal charge_level_changed(level: float)
signal charge_released(level: float)
signal charge_ability_equipped(ability_id: StringName)
signal charge_ability_unequipped(ability_id: StringName)
signal charge_ability_activated(ability_id: StringName, charge_level: float)

@export_group("Player")
@export_range(1.0, 100.0, 1.0, "suffix:px") var radius: float = 24.0

@export_group("Hit")
@export_range(0.0, 1000.0, 0.1) var damage: float = 0.0
@export_range(0.0, 0.1, 0.001) var damage_per_speed: float = 0.0
@export_range(-5000.0, 5000.0, 10.0, "suffix:px/s") var impulse_strength: float = 0.0
@export_range(0.0, 10.0, 0.05) var impulse_per_speed: float = 0.0

@export_group("Audio")
@export var hit_cue: SoundCue

@export_group("Camera")
@export var impact_shake: OneShotCameraShakeCue

var charge_level: float:
	get: return charge.level

var _shape: CircleShape2D = CircleShape2D.new()
var _position_interpolator: PhysicsPositionInterpolator = PhysicsPositionInterpolator.new()
var _feedback: Feedback

@onready var visual: CircleVisual = $Visual
@onready var sweep_hit: SweepHit = $SweepHit
@onready var movement: BallMovement = $Movement
@onready var hitstop: Hitstop = $Hitstop
@onready var boost: BallBoost = $Boost
@onready var brake: BallBrake = $Brake
@onready var charge: BallCharge = $Charge
@onready var charge_lines: ChargeLines = $ChargeLines
@onready var charge_ability_slot: ChargeAbilitySlot = $ChargeAbilitySlot
@onready var player_input: PlayerInput = $PlayerInput


func _ready() -> void:
	visual.radius = radius
	visual.position.y = -radius
	sweep_hit.position.y = -radius
	charge_lines.position.y = -radius
	_shape.radius = radius
	sweep_hit.shape = _shape
	global_position = get_global_mouse_position() + Vector2(0.0, radius)
	reset_position_interpolation()

	sweep_hit.hurtbox_detected.connect(_on_hurtbox_detected)
	boost.activated.connect(_on_boost_activated)
	boost.sound_requested.connect(sound_requested.emit)
	boost.setup(
		self,
		movement,
		hitstop,
		_position_interpolator.get_interpolated_global_position
	)
	brake.setup(movement)
	brake.started.connect(charge.start)
	brake.ended.connect(_on_brake_ended)
	charge.started.connect(charge_started.emit)
	charge.level_changed.connect(charge_level_changed.emit)
	charge.released.connect(charge_released.emit)
	charge_lines.setup(charge)
	charge_ability_slot.ability_equipped.connect(charge_ability_equipped.emit)
	charge_ability_slot.ability_unequipped.connect(charge_ability_unequipped.emit)
	charge_ability_slot.ability_activated.connect(charge_ability_activated.emit)
	charge_ability_slot.sound_requested.connect(sound_requested.emit)
	charge_ability_slot.setup(self)


func _physics_process(delta: float) -> void:
	var target_position := get_global_mouse_position() + Vector2(0.0, radius)
	hitstop.update()
	if hitstop.is_stopped:
		_position_interpolator.record_position(sweep_hit.global_position)
		return

	if brake.is_active:
		charge.update(delta)
		brake.update(delta)
	else:
		movement.update(delta, global_position, target_position)

	var motion := movement.velocity * delta
	if movement.velocity.is_zero_approx():
		sweep_hit.clear_contacts()
	else:
		sweep_hit.detect(motion)

	global_position += motion
	_position_interpolator.record_position(sweep_hit.global_position)


func setup(feedback: Feedback) -> void:
	_feedback = feedback
	sound_requested.connect(_feedback.sound_requested.emit)
	player_input.boost_requested.connect(request_boost)
	player_input.brake_pressed_changed.connect(set_brake_pressed)


func request_boost() -> bool:
	return boost.try_activate()


func set_brake_pressed(is_pressed: bool) -> void:
	brake.set_pressed(is_pressed)


func equip_charge_ability(definition: ChargeAbilityDefinition) -> bool:
	return charge_ability_slot.equip(definition)


func unequip_charge_ability() -> void:
	charge_ability_slot.unequip()


func get_equipped_charge_ability() -> ChargeAbilityDefinition:
	return charge_ability_slot.get_equipped_definition()


func reset_position_interpolation() -> void:
	reset_physics_interpolation()
	_position_interpolator.reset(sweep_hit.global_position)


func _on_hurtbox_detected(hurtbox: Hurtbox, hit_direction: Vector2) -> void:
	var impact_speed := movement.velocity.length()
	var hit := HitData.new()
	hit.attacker = self
	hit.damage = damage + impact_speed * damage_per_speed
	hit.knockback = impulse_strength + impact_speed * impulse_per_speed
	hit.hit_direction = hit_direction
	hit.hit_position = hurtbox.global_position
	hurtbox.receive_hit(hit)

	hitstop.request()
	hit_landed.emit(hurtbox.global_position, impact_speed)
	if impact_shake != null and impact_speed >= 1000.0:
		var speed_ratio := clampf(inverse_lerp(1000.0, 7000.0, impact_speed), 0.0, 1.0)
		_feedback.camera_shake_requested.emit(
			CameraShakeRequest.play(impact_shake, hit_direction, pow(speed_ratio, 1.8))
		)

	if hit_cue != null:
		sound_requested.emit(SoundRequest.new(hit_cue, hurtbox.global_position, self))


func _on_boost_activated() -> void:
	brake.interrupt_until_released()


func _on_brake_ended(_duration: float) -> void:
	charge.release()
