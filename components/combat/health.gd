class_name Health
extends Node

signal health_changed(current_health: float, max_health: float)
signal died

@export_range(1.0, 100000.0, 1.0) var max_health: float = 100.0:
	set(value):
		max_health = maxf(value, 1.0)
		current_health = minf(current_health, max_health)

var current_health: float = 100.0:
	set(value):
		current_health = clampf(value, 0.0, max_health)


func _ready() -> void:
	current_health = max_health


func take_damage(amount: float) -> void:
	if amount <= 0.0 or current_health <= 0.0:
		return

	var previous_health := current_health
	current_health -= amount
	if is_equal_approx(current_health, previous_health):
		return

	health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0 or current_health >= max_health:
		return

	var previous_health := current_health
	current_health += amount
	if is_equal_approx(current_health, previous_health):
		return

	health_changed.emit(current_health, max_health)


func set_max_health(value: float) -> void:
	var new_max_health := maxf(value, 1.0)
	if is_equal_approx(max_health, new_max_health):
		return

	max_health = new_max_health
	health_changed.emit(current_health, max_health)


func reset() -> void:
	if is_equal_approx(current_health, max_health):
		return

	current_health = max_health
	health_changed.emit(current_health, max_health)
