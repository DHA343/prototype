@tool
extends PinballBall

const PhysicsEnemy = preload("res://tests/enemy/physics_enemy.gd")
const BallOutline = preload("res://tests/ball/ball_outline.gd")

var hit_reaction: PhysicsEnemy.HitReaction = PhysicsEnemy.HitReaction.FLIP_KNOCKBACK
var flip_window: float = 0.25
var after_flip: PhysicsEnemy.HitReaction = PhysicsEnemy.HitReaction.STAGGER

var _physics_time: float = 0.0
var _flipped_at: float = -INF

@onready var _outline: BallOutline = $KnockbackOutline


func _ready() -> void:
	super._ready()
	_motion.trajectory_changed = _on_trajectory_changed
	_outline.radius = radius


func reset_at(point: Vector2, initial_velocity: Vector2 = Vector2.ZERO) -> void:
	super.reset_at(point, initial_velocity)
	_physics_time = 0.0
	_flipped_at = -INF
	_outline.hide()


func advance(
	delta: float, swings: Array[PinballFlipper.Swing] = [], enemies: Array[Enemy] = [],
) -> void:
	if not active:
		return
	super.advance(delta, swings, enemies)
	_physics_time += delta
	_outline.visible = hit_reaction == PhysicsEnemy.HitReaction.FLIP_KNOCKBACK and _can_knockback(0.0)


func _hit_enemy(
	enemy: Enemy, point: Vector2, normal: Vector2, impact_speed: float, hit_time: float,
) -> void:
	var target := enemy as PhysicsEnemy
	if target != null:
		target.hit_reaction = hit_reaction
		if hit_reaction == PhysicsEnemy.HitReaction.FLIP_KNOCKBACK:
			target.hit_reaction = (
				PhysicsEnemy.HitReaction.KNOCKBACK if _can_knockback(hit_time) else after_flip
			)
	super._hit_enemy(enemy, point, normal, impact_speed, hit_time)


func _refresh_shape() -> void:
	super._refresh_shape()
	if is_node_ready():
		_outline.radius = radius


func _on_trajectory_changed(is_flip: bool, time_in_step: float) -> void:
	_flipped_at = _physics_time + time_in_step if is_flip else -INF


func _can_knockback(time_in_step: float) -> bool:
	return _physics_time + time_in_step - _flipped_at < flip_window
