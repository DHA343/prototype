@abstract
class_name ChargeAbility
extends Node

@warning_ignore("unused_signal")
signal sound_requested(request: SoundRequest)

var _ball: Player
var _definition: ChargeAbilityDefinition


func setup(ball: Player, definition: ChargeAbilityDefinition) -> void:
	assert(ball != null, "ball must not be null.")
	assert(definition != null, "definition must not be null.")
	assert(_ball == null, "ChargeAbility must not be setup more than once.")

	_ball = ball
	_definition = definition
	_setup()


@abstract
func activate(charge_level: float) -> bool


func teardown() -> void:
	if _ball == null:
		return

	_teardown()
	_ball = null
	_definition = null


func get_definition() -> ChargeAbilityDefinition:
	return _definition


@abstract
func _setup() -> void


func _teardown() -> void:
	pass
