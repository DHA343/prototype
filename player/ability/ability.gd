class_name Ability
extends Node

@warning_ignore("unused_signal")
signal sound_requested(request: SoundRequest)
@warning_ignore("unused_signal")
signal camera_shake_requested(trauma: float)

@export_range(0.0, 0.5, 0.01, "suffix:s") var press_buffer_duration: float = 0.0

var _ability_user: Node
var _attack_root: Node2D


func setup(ability_user: Node, attack_root: Node2D) -> void:
	_ability_user = ability_user
	_attack_root = attack_root


func update(_delta: float) -> void:
	pass


func can_activate() -> bool:
	return true


func input_pressed(_aim_direction: Vector2) -> void:
	pass


func input_held(_delta: float, _aim_direction: Vector2) -> void:
	pass


func input_released(_aim_direction: Vector2) -> void:
	pass
