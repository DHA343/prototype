class_name OrbCharge
extends Node2D

signal started
signal level_changed(level: float)
signal released(level: float)
signal ability_equipped(ability_id: StringName)
signal ability_unequipped(ability_id: StringName)
signal ability_activated(ability_id: StringName, charge_level: float)
signal sound_requested(request: SoundRequest)

@export_range(0.1, 5.0, 0.05, "suffix:s") var max_charge_time: float = 1.0

var level: float:
	get: return _level

var is_charging: bool:
	get: return _is_charging

var _charge_time: float = 0.0
var _level: float = 0.0
var _is_charging: bool = false

@onready var _lines: ChargeLines = $ChargeLines
@onready var _ability_slot: ChargeAbilitySlot = $ChargeAbilitySlot


func _ready() -> void:
	_lines.setup(self)
	_ability_slot.ability_equipped.connect(ability_equipped.emit)
	_ability_slot.ability_unequipped.connect(ability_unequipped.emit)
	_ability_slot.ability_activated.connect(ability_activated.emit)
	_ability_slot.sound_requested.connect(sound_requested.emit)


func setup(
	radius: float,
	spawn_parent: Node2D,
	get_spawn_position: Callable,
	get_sound_position: Callable,
	request_sound: Callable
) -> void:
	_lines.position.y = -radius
	_ability_slot.setup(
		self,
		spawn_parent,
		get_spawn_position,
		get_sound_position,
		request_sound
	)


func equip_ability(definition: ChargeAbilityDefinition) -> bool:
	return _ability_slot.equip(definition)


func unequip_ability() -> void:
	_ability_slot.unequip()


func get_equipped_definition() -> ChargeAbilityDefinition:
	return _ability_slot.get_equipped_definition()



func start() -> void:
	_charge_time = 0.0
	_level = 0.0
	_is_charging = true
	started.emit()
	level_changed.emit(_level)


func update(delta: float) -> void:
	assert(delta >= 0.0, "delta must not be negative.")

	if not _is_charging or _level >= 1.0:
		return

	_charge_time = minf(_charge_time + delta, max_charge_time)
	_level = _charge_time / max_charge_time
	level_changed.emit(_level)


func release() -> void:
	if not _is_charging:
		return

	_is_charging = false
	var released_level := _level
	released.emit(released_level)

	_charge_time = 0.0
	_level = 0.0
	level_changed.emit(_level)
