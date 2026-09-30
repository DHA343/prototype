@abstract
class_name ChargeAbility
extends Node

@warning_ignore("unused_signal")
signal sound_requested(request: SoundRequest)

var _definition: ChargeAbilityDefinition
var _spawn_parent: Node2D
var _get_spawn_position: Callable
var _get_sound_position: Callable
var _request_sound: Callable


func setup(
	definition: ChargeAbilityDefinition,
	spawn_parent: Node2D,
	get_spawn_position: Callable,
	get_sound_position: Callable,
	request_sound: Callable
) -> void:
	assert(definition != null, "definition must not be null.")
	assert(spawn_parent != null, "spawn_parent must not be null.")
	assert(get_spawn_position.is_valid(), "get_spawn_position must be valid.")
	assert(get_sound_position.is_valid(), "get_sound_position must be valid.")
	assert(request_sound.is_valid(), "request_sound must be valid.")
	assert(_definition == null, "Setup must not be called more than once.")

	_definition = definition
	_spawn_parent = spawn_parent
	_get_spawn_position = get_spawn_position
	_get_sound_position = get_sound_position
	_request_sound = request_sound
	_setup()


@abstract
func activate(charge_level: float) -> bool


func teardown() -> void:
	if _definition == null:
		return

	_teardown()
	_definition = null
	_spawn_parent = null
	_get_spawn_position = Callable()
	_get_sound_position = Callable()
	_request_sound = Callable()


func get_definition() -> ChargeAbilityDefinition:
	return _definition


@abstract
func _setup() -> void


func _teardown() -> void:
	pass
