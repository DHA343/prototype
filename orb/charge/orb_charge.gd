class_name OrbCharge
extends Node

signal started
signal level_changed(level: float)
signal released(level: float)

@export_range(0.1, 5.0, 0.05, "suffix:s") var max_charge_time: float = 1.0

var level: float:
	get: return _level

var is_charging: bool:
	get: return _is_charging

var _charge_time: float = 0.0
var _level: float = 0.0
var _is_charging: bool = false


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
