class_name Enemy
extends Node2D

signal died(enemy: Enemy)
## Reports attack damage and total knockback velocity, including on a lethal hit.
signal damaged(requested_damage: float, hit_position: Vector2, resulting_knockback_velocity: Vector2)

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

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var knockback: Knockback = $Knockback
@onready var hit_scale_reaction: HitScaleReaction = $HitScaleReaction


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	health.died.connect(_on_health_died)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	var chase_velocity := _get_chase_velocity()
	knockback.update(delta)

	global_position += (chase_velocity + knockback.velocity) * delta


## Called after adding the enemy and assigning its world position.
func start(target: Node2D) -> void:
	_target = target
	set_physics_process(true)


func _get_chase_velocity() -> Vector2:
	if not is_instance_valid(_target):
		return Vector2.ZERO

	var offset := _target.global_position - global_position
	if offset.length() <= stop_distance:
		return Vector2.ZERO

	return offset.normalized() * move_speed


func _on_hurtbox_hit_received(hit: HitData) -> void:
	health.take_damage(hit.damage)

	knockback.apply_hit(hit, knockback_resistance)
	hit_scale_reaction.play()
	damaged.emit(hit.damage, hit.hit_position, knockback.velocity)


func _on_health_died() -> void:
	died.emit(self)
	queue_free()
