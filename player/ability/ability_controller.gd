class_name AbilityController
extends Node

signal sound_requested(request: SoundRequest)
signal camera_shake_requested(request: CameraShakeRequest)

var _slots: Dictionary[StringName, AbilitySlot] = {}
var _ability_user: Node
var _player_input: PlayerInput
var _attack_root: Node2D
var _aim_direction: Vector2 = Vector2.RIGHT


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_update_aim_direction()
	for slot: AbilitySlot in _slots.values():
		var action := slot.input_action
		slot.update_input(
			delta,
			_player_input.is_action_just_pressed(action),
			_player_input.is_action_pressed(action),
			_player_input.is_action_just_released(action),
			_aim_direction
		)


func setup(ability_user: Node, player_input: PlayerInput, attack_root: Node2D) -> void:
	_ability_user = ability_user
	_player_input = player_input
	_attack_root = attack_root
	_collect_slots()
	for slot: AbilitySlot in _slots.values():
		slot.setup(_ability_user, _attack_root)
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


func _collect_slots() -> void:
	_slots.clear()
	for child: Node in get_children():
		var slot := child as AbilitySlot
		if slot == null:
			continue
		assert(not slot.slot_id.is_empty(), "Ability slot_id is required.")
		assert(not _slots.has(slot.slot_id), "Ability slot_id must be unique.")
		assert(InputMap.has_action(slot.input_action), "Ability input action is missing.")
		_slots[slot.slot_id] = slot
		slot.ability_changed.connect(_on_slot_ability_changed)


func _get_slot(slot_id: StringName) -> AbilitySlot:
	var slot := _slots.get(slot_id) as AbilitySlot
	if slot == null:
		push_error("Ability slot was not found.")
	return slot


func _update_aim_direction() -> void:
	var aim_offset := _player_input.get_aim_offset(_attack_root)
	if not aim_offset.is_zero_approx():
		_aim_direction = aim_offset.normalized()


func _on_slot_ability_changed(previous_ability: Ability, current_ability: Ability) -> void:
	if previous_ability != null:
		if previous_ability.sound_requested.is_connected(_on_ability_sound_requested):
			previous_ability.sound_requested.disconnect(_on_ability_sound_requested)
		if previous_ability.camera_shake_requested.is_connected(_on_ability_camera_shake_requested):
			previous_ability.camera_shake_requested.disconnect(_on_ability_camera_shake_requested)
	if current_ability != null:
		current_ability.sound_requested.connect(_on_ability_sound_requested)
		current_ability.camera_shake_requested.connect(_on_ability_camera_shake_requested)


func _on_ability_sound_requested(request: SoundRequest) -> void:
	sound_requested.emit(request)


func _on_ability_camera_shake_requested(request: CameraShakeRequest) -> void:
	camera_shake_requested.emit(request)
