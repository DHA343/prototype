class_name Enemy
extends Node2D

signal died(enemy: Enemy)
## Reports attack damage and total knockback velocity, including on a lethal hit.
signal damaged(requested_damage: float, hit_position: Vector2, resulting_knockback_velocity: Vector2)
signal sound_requested(request: SoundRequest)

@export_group("Crowd")
@export var crowd: CrowdSettings

@export_group("Combat")
@export_range(0.0, 1.0, 0.01) var knockback_resistance: float = 0.0:
	set(value):
		knockback_resistance = clampf(value, 0.0, 1.0)

@export_group("Audio")
@export var death_cue: SoundCue

@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var knockback: Knockback = $Knockback
@onready var hit_scale_reaction: HitScaleReaction = $HitScaleReaction
@onready var movement: EnemyMovement = $Movement
@onready var spawn_animation: EnemySpawnAnimation = $SpawnAnimation
@onready var _visual_root: Node2D = $VisualRoot
@onready var _visual: EnemyVisual = $VisualRoot/Visual


func _ready() -> void:
	hurtbox.hit_received.connect(_on_hurtbox_hit_received)
	health.died.connect(_on_health_died)
	health.health_changed.connect(_visual.update_health)
	_visual.update_health(health.current_health, health.max_health)
	spawn_animation.scale_changed.connect(_on_spawn_scale_changed)
	spawn_animation.grow_finished.connect(_on_spawn_grow_finished)
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	movement.update(delta, global_position)
	global_position += (movement.velocity + knockback.velocity) * delta
	knockback.update(delta)


## Called after adding the enemy and assigning its world position.
func start(area: SpawnArea) -> void:
	movement.territory = area
	hurtbox.set_enabled(false)
	spawn_animation.play()
	set_physics_process(true)


func _on_spawn_scale_changed(value: float) -> void:
	_visual_root.scale = Vector2.ONE * value


func _on_spawn_grow_finished() -> void:
	hurtbox.set_enabled(true)


func _on_hurtbox_hit_received(hit: HitData) -> void:
	# Stop the spawn tween and spring before handing the same visual to the hit reaction.
	spawn_animation.cancel()
	hurtbox.set_enabled(true)
	health.take_damage(hit.damage)

	knockback.apply_hit(hit, knockback_resistance)
	hit_scale_reaction.play()
	damaged.emit(hit.damage, hit.hit_position, knockback.velocity)


func _on_health_died() -> void:
	if death_cue != null:
		sound_requested.emit(SoundRequest.new(death_cue, global_position, self))
	died.emit(self)
	queue_free()
