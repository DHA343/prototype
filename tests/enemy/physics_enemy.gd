@tool
extends Enemy

enum HitReaction {
	STAGGER,
	SLOW,
	KNOCKBACK,
	FLIP_KNOCKBACK,
}

const ENEMY_COLLISION_LAYER: int = 3
const ENEMY_RESTITUTION: float = 0.1

var downward_knockback_scale: float = 1.0
var follows_route: bool = false
var hit_reaction: HitReaction = HitReaction.KNOCKBACK
var reaction_duration: float = 0.2
var slow_speed_ratio: float = 0.5

var _motion: PinballMotion = PinballMotion.new(self)
var _reaction_remaining: float = 0.0
var _reaction_speed_ratio: float = 1.0


func _ready() -> void:
	super._ready()
	_motion.native_contact = _resolve_contact
	damaged.connect(_on_damaged)


func receive_ball_hit(amount: float, point: Vector2, impulse: Vector2) -> void:
	var knocks_back := hit_reaction == HitReaction.KNOCKBACK
	if not super.receive_hit(amount, point, impulse if knocks_back else Vector2.ZERO):
		return
	_reaction_remaining = 0.0 if knocks_back else reaction_duration
	_reaction_speed_ratio = 0.0 if hit_reaction == HitReaction.STAGGER else slow_speed_ratio


func advance_physics(
	delta: float, swings: Array[PinballFlipper.Swing], ball: PinballBall,
	gravity: float, max_speed: float, collide_with_enemies: bool,
) -> void:
	_advance_presentation(delta)
	if follows_route:
		_advance_route(delta)
	else:
		_repath_remaining = 0.0
	_reaction_remaining = maxf(0.0, _reaction_remaining - delta)
	var can_collide := collide_with_enemies and get_collision_layer_value(ENEMY_COLLISION_LAYER)
	set_collision_mask_value(ENEMY_COLLISION_LAYER, can_collide)
	_motion.radius = radius
	_motion.gravity = gravity
	_motion.max_speed = max_speed
	_motion.boundary = ball.boundary
	_motion.flippers = ball.flippers
	_motion.advance(delta, swings)
	if can_collide:
		force_update_transform()


func knockback_velocity() -> Vector2:
	# Hit impulses are already included in velocity.
	return Vector2.ZERO


func _on_damaged(_amount: float, _point: Vector2, impulse: Vector2) -> void:
	if impulse.y > 0.0:
		impulse.y *= downward_knockback_scale
	velocity += impulse


func _advance_route(delta: float) -> void:
	var desired := _route_velocity(delta)
	if _reaction_remaining > 0.0:
		var forward := desired.normalized()
		desired *= _reaction_speed_ratio
		var excess := velocity.dot(forward) - desired.length()
		velocity -= forward * maxf(0.0, excess)
	velocity = velocity.move_toward(desired, acceleration * delta)


func _resolve_contact(collision: KinematicCollision2D) -> void:
	var other := collision.get_collider() as Enemy
	if other == null:
		_motion.resolve_contact(collision)
		return

	var normal := collision.get_normal()
	var approach_speed := -(velocity - other.velocity).dot(normal)
	if approach_speed <= 0.0:
		return
	# Equal masses share the normal impulse, leaving their tangential velocities alone.
	var impulse := normal * (approach_speed * (1.0 + ENEMY_RESTITUTION) * 0.5)
	velocity += impulse
	other.velocity = (other.velocity - impulse).limit_length(_motion.max_speed)
