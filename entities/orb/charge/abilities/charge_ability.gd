@abstract
class_name ChargeAbility
extends Node

@warning_ignore("unused_signal")
signal sound_requested(request: SoundRequest)

var _orb: Orb
var _definition: ChargeAbilityDefinition


func setup(orb: Orb, definition: ChargeAbilityDefinition) -> void:
	assert(orb != null, "orb must not be null.")
	assert(definition != null, "definition must not be null.")
	assert(_orb == null, "ChargeAbility must not be setup more than once.")

	_orb = orb
	_definition = definition
	_setup()


@abstract
func activate(charge_level: float) -> bool


func teardown() -> void:
	if _orb == null:
		return

	_teardown()
	_orb = null
	_definition = null


func get_definition() -> ChargeAbilityDefinition:
	return _definition


@abstract
func _setup() -> void


func _teardown() -> void:
	pass
