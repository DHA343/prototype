class_name ChargeAbilitySlot
extends Node

signal ability_equipped(ability_id: StringName)
signal ability_unequipped(ability_id: StringName)
signal ability_activated(ability_id: StringName, charge_level: float)
signal sound_requested(request: SoundRequest)

@export var initial_definition: ChargeAbilityDefinition

var _spawn_parent: Node2D
var _get_spawn_position: Callable
var _get_sound_position: Callable
var _request_sound: Callable
var _ability: ChargeAbility


func setup(
	charge: OrbCharge,
	spawn_parent: Node2D,
	get_spawn_position: Callable,
	get_sound_position: Callable,
	request_sound: Callable
) -> void:
	assert(charge != null, "charge must not be null.")
	assert(spawn_parent != null, "spawn_parent must not be null.")
	assert(get_spawn_position.is_valid(), "get_spawn_position must be valid.")
	assert(get_sound_position.is_valid(), "get_sound_position must be valid.")
	assert(request_sound.is_valid(), "request_sound must be valid.")
	assert(_spawn_parent == null, "Setup must not be called more than once.")

	_spawn_parent = spawn_parent
	_get_spawn_position = get_spawn_position
	_get_sound_position = get_sound_position
	_request_sound = request_sound
	charge.released.connect(_on_charge_released)

	if initial_definition != null:
		var was_equipped := equip(initial_definition)
		assert(was_equipped, "initial_definition must be a valid charge ability definition.")


func equip(definition: ChargeAbilityDefinition) -> bool:
	assert(_spawn_parent != null, "Setup must be called before equipping an ability.")

	if not _is_definition_valid(definition):
		return false

	var instance := definition.ability_scene.instantiate()
	if not instance is ChargeAbility:
		push_error("The root node of ability_scene must inherit ChargeAbility.")
		instance.free()
		return false

	unequip()

	_ability = instance as ChargeAbility
	add_child(_ability)
	_ability.sound_requested.connect(sound_requested.emit)
	_ability.setup(
		definition,
		_spawn_parent,
		_get_spawn_position,
		_get_sound_position,
		_request_sound
	)
	ability_equipped.emit(definition.id)
	return true


func unequip() -> void:
	if _ability == null:
		return

	var ability_id := _ability.get_definition().id
	_ability.teardown()
	_ability.queue_free()
	_ability = null
	ability_unequipped.emit(ability_id)


func get_equipped_definition() -> ChargeAbilityDefinition:
	if _ability == null:
		return null

	return _ability.get_definition()


func _on_charge_released(level: float) -> void:
	if _ability == null or not _ability.activate(level):
		return

	ability_activated.emit(_ability.get_definition().id, level)


func _is_definition_valid(definition: ChargeAbilityDefinition) -> bool:
	if definition == null:
		push_error("ChargeAbilityDefinition must not be null.")
		return false

	if definition.id.is_empty():
		push_error("ChargeAbilityDefinition.id must not be empty.")
		return false

	if definition.ability_scene == null:
		push_error("ChargeAbilityDefinition.ability_scene must not be null.")
		return false

	return true
