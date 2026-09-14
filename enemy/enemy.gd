class_name Enemy
extends Node2D

signal died(enemy: Enemy)

@export_group("Movement")
@export_range(0.0, 1000.0, 10.0, "suffix:unit/s") var move_speed: float = 180.0
@export_range(0.0, 200.0, 1.0, "suffix:unit") var stop_distance: float = 36.0

@export_group("Crowd")
@export var crowd: CrowdSettings

@export_group("Combat")
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.0:
	set(value):
		knockback_resistance = clampf(value, 0.0, 1.0)

var _target: Node2D = null
var _crowd_manager: CrowdManager = null
var _is_registered: bool = false

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var knockback: Knockback = $Knockback


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	health.died.connect(_on_health_died)


func _exit_tree() -> void:
	if _is_registered and is_instance_valid(_crowd_manager):
		_crowd_manager.unregister_member(self)

	_is_registered = false


func _physics_process(delta: float) -> void:
	var chase_velocity := _get_chase_velocity()
	knockback.update(delta)

	global_position += (chase_velocity + knockback.velocity) * delta


func setup(target: Node2D, crowd_manager: CrowdManager) -> void:
	_unregister_from_crowd_manager()

	_target = target
	_crowd_manager = crowd_manager
	if not is_instance_valid(_crowd_manager):
		return
	if crowd == null:
		push_error("Crowd settings are not assigned.")
		return

	_crowd_manager.register_member(
		self,
		crowd.radius,
		crowd.avoidance_radius,
		crowd.response
	)
	_is_registered = true


func _get_chase_velocity() -> Vector2:
	if not is_instance_valid(_target):
		return Vector2.ZERO

	var offset := _target.global_position - global_position
	if offset.length() <= stop_distance:
		return Vector2.ZERO

	return offset.normalized() * move_speed


func _on_hurtbox_hit_received(hit: HitData) -> void:
	health.take_damage(hit.damage)

	var direction := hit.hit_direction.normalized()
	var multiplier := 1.0 - knockback_resistance
	var knockback_velocity := direction * hit.knockback * multiplier
	knockback.apply(knockback_velocity)


func _on_health_died() -> void:
	died.emit(self)
	queue_free()


func _unregister_from_crowd_manager() -> void:
	if _is_registered and is_instance_valid(_crowd_manager):
		_crowd_manager.unregister_member(self)

	_is_registered = false
