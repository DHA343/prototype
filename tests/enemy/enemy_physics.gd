extends PinballLab

const PhysicsEnemy = preload("res://tests/enemy/physics_enemy.gd")
const ExperimentBall = preload("res://tests/enemy/ball.gd")

@export_group("Enemy Physics", "enemy_")
@export var enemy_gravity_enabled: bool = true
@export_range(0.0, 4200.0, 30.0, "suffix:px/s²") var enemy_gravity: float = 1500.0
## 重力オフ時に穴へ向かう速度。
@export_range(0.0, 600.0, 15.0, "suffix:px/s") var enemy_route_speed: float = 120.0
@export_range(300.0, 7200.0, 30.0, "suffix:px/s") var enemy_max_speed: float = 3600.0
@export var enemy_collisions_enabled: bool = true
## 敵に当たったボールの反発係数。
@export_range(0.0, 1.0, 0.01) var enemy_ball_restitution: float = 0.8
## ボールから受けるノックバックの軽減率。
@export_range(0.0, 1.0, 0.01) var enemy_knockback_resistance: float = 0.0
## ボールから受ける下向きノックバックの倍率。1は従来の強さ。
@export_range(0.0, 1.0, 0.01) var enemy_downward_knockback_scale: float = 0.25

@export_group("Ball", "ball_")
## 命中時のダメージと反応を適用しながら敵を通過する。
@export var ball_pierces_enemies: bool = false

@export_group("Ball Hit Reaction", "reaction_")
@export var reaction_mode: PhysicsEnemy.HitReaction = PhysicsEnemy.HitReaction.FLIP_KNOCKBACK
## フリップで打ち出してからノックバックが有効な時間。途中で反射すると終了する。
@export_range(0.0, 1.0, 0.01, "suffix:s") var reaction_flip_window: float = 0.25
@export_enum("Stagger", "Slow") var reaction_after_flip: int = PhysicsEnemy.HitReaction.STAGGER
## ひるみと減速の持続時間。
@export_range(0.0, 1.0, 0.01, "suffix:s") var reaction_duration: float = 0.2
## 減速中の経路移動速度の倍率。
@export_range(0.0, 1.0, 0.05) var reaction_slow_speed_ratio: float = 0.5


func advance(delta: float) -> void:
	var experiment_ball := ball as ExperimentBall
	experiment_ball.pierces_enemies = ball_pierces_enemies
	experiment_ball.hit_reaction = reaction_mode
	experiment_ball.flip_window = reaction_flip_window
	experiment_ball.after_flip = reaction_after_flip as PhysicsEnemy.HitReaction
	super.advance(delta)


func _advance_enemies(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	var gravity := enemy_gravity if enemy_gravity_enabled else 0.0
	if enemy_collisions_enabled:
		_separate_coincident_enemies()
	for index in range(enemies.size() - 1, -1, -1):
		var enemy := enemies[index] as PhysicsEnemy
		enemy.restitution = enemy_ball_restitution
		enemy.knockback_resistance = enemy_knockback_resistance
		enemy.downward_knockback_scale = enemy_downward_knockback_scale
		enemy.reaction_duration = reaction_duration
		enemy.slow_speed_ratio = reaction_slow_speed_ratio
		enemy.follows_route = not enemy_gravity_enabled
		enemy.move_speed = minf(enemy_route_speed, enemy_max_speed)
		enemy.advance_physics(
			delta, swings, ball, gravity, enemy_max_speed, enemy_collisions_enabled,
		)
		if boundary.to_local(enemy.global_position).y > boundary.bottom + 120.0:
			enemy.finish(Enemy.ExitReason.ESCAPED)


func _separate_coincident_enemies() -> void:
	var occupied_centers: Dictionary[Vector2, bool] = {}
	for enemy: Enemy in enemies:
		var center := enemy.global_position
		# Coincident circles need a separation direction for collision recovery.
		while occupied_centers.has(center):
			center.x += PinballMotion.CONTACT_MARGIN
		if center != enemy.global_position:
			enemy.global_position = center
			enemy.force_update_transform()
		occupied_centers[center] = true
