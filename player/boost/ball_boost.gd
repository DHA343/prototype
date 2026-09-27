class_name BallBoost
extends Node

signal activated
signal cooldown_started(duration: float)
signal cooldown_finished
signal sound_requested(request: SoundRequest)

@export_range(0.0, 10.0, 0.01) var speed_multiplier: float = 0.1
@export_range(0.0, 5000.0, 10.0, "suffix:px/s") var speed_constant: float = 1500.0
@export_range(0.0, 10.0, 0.01, "suffix:s") var cooldown: float = 0.4
@export var activation_cue: SoundCue

var _ball: Player
var _movement: BallMovement
var _hitstop: Hitstop
var _cooldown_remaining: float = 0.0

@onready var _boost_trail: BoostTrail = $BoostTrail


func _physics_process(delta: float) -> void:
	if _cooldown_remaining <= 0.0:
		return

	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	if _cooldown_remaining <= 0.0:
		cooldown_finished.emit()


func setup(
	ball: Player,
	movement: BallMovement,
	hitstop: Hitstop,
	get_interpolated_position: Callable
) -> void:
	assert(ball != null, "ball must not be null.")
	assert(movement != null, "movement must not be null.")
	assert(hitstop != null, "hitstop must not be null.")
	assert(get_interpolated_position.is_valid(), "get_interpolated_position must be valid.")
	assert(activation_cue != null, "activation_cue must not be null.")
	assert(_ball == null, "BallBoost must not be setup more than once.")

	_ball = ball
	_movement = movement
	_hitstop = hitstop
	_boost_trail.setup(ball, get_interpolated_position)


func try_activate() -> bool:
	assert(_movement != null, "BallBoost must be setup before activation.")

	if _cooldown_remaining > 0.0:
		return false

	var velocity := _movement.velocity
	var added_speed := velocity.length() * speed_multiplier + speed_constant
	_movement.add_velocity(_movement.heading * added_speed)
	_hitstop.cancel()
	_boost_trail.play()

	if cooldown > 0.0:
		_cooldown_remaining = cooldown
		cooldown_started.emit(cooldown)

	activated.emit()
	sound_requested.emit(SoundRequest.new(activation_cue, _ball.global_position, self))
	return true


func get_cooldown_remaining() -> float:
	return _cooldown_remaining
