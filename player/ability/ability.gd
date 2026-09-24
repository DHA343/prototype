class_name Ability
extends Node

@export_range(0.0, 0.5, 0.01, "suffix:s") var press_buffer_duration: float = 0.0

var _ability_user: Node
var _attack_root: Node2D
var _feedback: Feedback


func setup(ability_user: Node, attack_root: Node2D, feedback: Feedback) -> void:
	_ability_user = ability_user
	_attack_root = attack_root
	_feedback = feedback


func update(_delta: float, _aim_direction: Vector2) -> void:
	pass


func can_activate() -> bool:
	return true


func blocks_other_abilities() -> bool:
	return false


func get_movement_multiplier() -> float:
	return 1.0


func input_pressed(_aim_direction: Vector2) -> void:
	pass


func input_held(_delta: float, _aim_direction: Vector2) -> void:
	pass


func input_released(_aim_direction: Vector2) -> void:
	pass
