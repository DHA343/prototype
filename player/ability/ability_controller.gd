class_name AbilityController
extends Node

var _slots: Dictionary[StringName, AbilitySlot] = {}
var _ordered_slots: Array[AbilitySlot] = []
var _ability_user: Node
var _player_input: PlayerInput
var _attack_root: Node2D
var _aim_direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_update_aim_direction()
	for slot: AbilitySlot in _ordered_slots:
		var action := slot.input_action
		slot.update_input(
			delta,
			_player_input.is_action_just_pressed(action),
			_player_input.is_action_pressed(action),
			_player_input.is_action_just_released(action),
			_aim_direction,
			not _is_blocked_by_other_slot(slot)
		)


func setup(
	ability_user: Node,
	player_input: PlayerInput,
	attack_root: Node2D,
	feedback: Feedback
) -> void:
	_ability_user = ability_user
	_player_input = player_input
	_attack_root = attack_root
	_collect_slots()
	for slot: AbilitySlot in _slots.values():
		slot.setup(_ability_user, _attack_root, feedback)
	set_process(true)


func set_ability(slot_id: StringName, ability_scene: PackedScene) -> bool:
	var slot := _get_slot(slot_id)
	return slot != null and slot.set_ability(ability_scene)


func clear_ability(slot_id: StringName) -> void:
	var slot := _get_slot(slot_id)
	if slot != null:
		slot.clear_ability()


func get_ability(slot_id: StringName) -> Ability:
	var slot := _get_slot(slot_id)
	return slot.get_ability() if slot != null else null


func get_movement_multiplier() -> float:
	var multiplier := 1.0
	for slot: AbilitySlot in _ordered_slots:
		multiplier = minf(multiplier, slot.get_movement_multiplier())
	return multiplier


func _collect_slots() -> void:
	_slots.clear()
	_ordered_slots.clear()
	for child: Node in get_children():
		var slot := child as AbilitySlot
		if slot == null:
			continue
		assert(not slot.slot_id.is_empty(), "Ability slot_id is required.")
		assert(not _slots.has(slot.slot_id), "Ability slot_id must be unique.")
		assert(InputMap.has_action(slot.input_action), "Ability input action is missing.")
		_slots[slot.slot_id] = slot
		_ordered_slots.append(slot)
	_ordered_slots.sort_custom(func(a: AbilitySlot, b: AbilitySlot) -> bool: return a.input_priority > b.input_priority)


func _is_blocked_by_other_slot(current_slot: AbilitySlot) -> bool:
	for slot: AbilitySlot in _ordered_slots:
		if slot != current_slot and slot.blocks_other_abilities():
			return true
	return false


func _get_slot(slot_id: StringName) -> AbilitySlot:
	var slot := _slots.get(slot_id) as AbilitySlot
	if slot == null:
		push_error("Ability slot was not found.")
	return slot


func _update_aim_direction() -> void:
	var aim_offset := _player_input.get_aim_offset(_attack_root)
	if not aim_offset.is_zero_approx():
		_aim_direction = aim_offset.normalized()
