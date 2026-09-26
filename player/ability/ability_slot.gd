class_name AbilitySlot
extends Node

signal ability_changed(previous_ability: Ability, current_ability: Ability)

@export var slot_id: StringName
@export var input_action: StringName
@export var initial_ability_scene: PackedScene
@export_range(0, 10, 1) var input_priority: int = 0

var _ability: Ability
var _ability_user: Node
var _ability_origin: Node2D
var _feedback: Feedback
var _is_setup: bool = false
var _has_buffered_press: bool = false
var _buffer_remaining: float = 0.0


func setup(ability_user: Node, ability_origin: Node2D, feedback: Feedback) -> void:
	_ability_user = ability_user
	_ability_origin = ability_origin
	_feedback = feedback
	_is_setup = true
	if _ability != null:
		_ability.setup(_ability_user, _ability_origin, _feedback)
	elif initial_ability_scene != null:
		set_ability(initial_ability_scene)


func set_ability(ability_scene: PackedScene) -> bool:
	if ability_scene == null:
		push_error("Ability scene is required.")
		return false

	var instance := ability_scene.instantiate()
	var next_ability := instance as Ability
	if next_ability == null:
		push_error("Ability scene must have an Ability root node.")
		instance.queue_free()
		return false

	var previous_ability := _ability
	_discard_buffered_press()
	_ability = next_ability
	if previous_ability != null:
		remove_child(previous_ability)

	add_child(next_ability)
	if _is_setup:
		next_ability.setup(_ability_user, _ability_origin, _feedback)
	ability_changed.emit(previous_ability, next_ability)
	if previous_ability != null:
		previous_ability.queue_free()
	return true


func clear_ability() -> void:
	_discard_buffered_press()
	if _ability == null:
		return

	var previous_ability := _ability
	_ability = null
	remove_child(previous_ability)
	ability_changed.emit(previous_ability, null)
	previous_ability.queue_free()


func get_ability() -> Ability:
	return _ability


func blocks_other_abilities() -> bool:
	return _ability != null and _ability.blocks_other_abilities()


func get_movement_multiplier() -> float:
	return _ability.get_movement_multiplier() if _ability != null else 1.0


func update_input(
	delta: float,
	just_pressed: bool,
	is_pressed: bool,
	just_released: bool,
	aim_direction: Vector2,
	allow_input: bool = true
) -> void:
	if _ability == null:
		return

	_ability.update(delta, aim_direction)
	_update_buffer(delta)
	if not allow_input:
		_discard_buffered_press()
		return
	if just_pressed:
		_discard_buffered_press()
		if _ability.can_activate():
			_ability.input_pressed(aim_direction)
		elif _ability.press_buffer_duration > 0.0:
			_has_buffered_press = true
			_buffer_remaining = _ability.press_buffer_duration
	if _has_buffered_press and _ability.can_activate():
		_discard_buffered_press()
		_ability.input_pressed(aim_direction)
	if is_pressed:
		_ability.input_held(delta, aim_direction)
	if just_released:
		_ability.input_released(aim_direction)


func _update_buffer(delta: float) -> void:
	if not _has_buffered_press:
		return
	_buffer_remaining -= maxf(delta, 0.0)
	if _buffer_remaining <= 0.0:
		_discard_buffered_press()


func _discard_buffered_press() -> void:
	_has_buffered_press = false
	_buffer_remaining = 0.0
