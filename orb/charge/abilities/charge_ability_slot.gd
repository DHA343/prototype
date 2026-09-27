class_name ChargeAbilitySlot
extends Node

signal ability_equipped(ability_id: StringName)
signal ability_unequipped(ability_id: StringName)
signal ability_activated(ability_id: StringName, charge_level: float)
signal sound_requested(request: SoundRequest)

@export var initial_definition: ChargeAbilityDefinition

var _orb: Orb
var _ability: ChargeAbility


func setup(orb: Orb) -> void:
	assert(orb != null, "orb must not be null.")
	assert(_orb == null, "ChargeAbilitySlot must not be setup more than once.")

	_orb = orb
	orb.charge_released.connect(_on_charge_released)

	if initial_definition != null:
		var was_equipped := equip(initial_definition)
		assert(was_equipped, "initial_definition must be a valid charge ability definition.")


func equip(definition: ChargeAbilityDefinition) -> bool:
	assert(_orb != null, "ChargeAbilitySlot must be setup before equipping an ability.")

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
	_ability.setup(_orb, definition)
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
