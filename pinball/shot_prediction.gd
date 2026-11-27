class_name ShotPrediction
extends RefCounted

const STEP: float = 1.0 / 240.0

var _query := PhysicsShapeQueryParameters2D.new()
var _excluded: Array[RID] = []
var _ball_rid: RID


func predict(ball: PinballBall, flippers: PinballFlippers) -> Vector2:
	if not ball.active or flippers.is_target_disabled(ball.get_instance_id()):
		return Vector2.ZERO
	var swings := flippers.plan_motion(true, true)
	if swings.is_empty():
		return Vector2.ZERO

	var horizon := flippers.swing_angle / flippers.raise_speed
	var position := ball.global_position
	var reach := ball.radius + ball.max_speed * horizon
	var reachable := false
	for swing: PinballFlipper.Swing in swings:
		var distance := swing.reach + reach
		if position.distance_squared_to(swing.origin) <= distance * distance:
			reachable = true
			break
	if not reachable:
		return Vector2.ZERO

	_prepare_query(ball, swings)
	var space := ball.get_world_2d().direct_space_state
	_query.transform = Transform2D(0.0, position)
	_query.motion = Vector2.ZERO
	# Casts ignore colliders that already overlap the query shape.
	if not space.intersect_shape(_query, 1).is_empty():
		return Vector2.ZERO

	var velocity := ball.velocity
	var elapsed := 0.0
	var step_limit := flippers.motion_step_limit(ball.radius, true, true)
	while elapsed < horizon:
		var step := minf(minf(STEP, step_limit), horizon - elapsed)
		velocity = ball.step_velocity(velocity, step)
		_query.transform = Transform2D(0.0, position)
		_query.motion = velocity * step
		var travel := space.cast_motion(_query)
		var collision_time := step * travel[0]
		var hit := flippers.first_contact(swings, position, velocity, ball.radius, elapsed,
			collision_time)
		if not hit.is_empty() and (travel[0] >= 1.0 or hit.time < collision_time):
			var approach_speed := PinballMotion.flipper_approach_speed(velocity, hit)
			if PinballMotion.is_flip_shot(hit, approach_speed):
				var direction := flippers.outward_shot_direction(hit)
				if direction != Vector2.ZERO:
					return flippers.shot_velocity(velocity, hit, direction).limit_length(ball.max_speed)
			return Vector2.ZERO
		if travel[0] < 1.0:
			return Vector2.ZERO
		position += _query.motion
		elapsed += step
	return Vector2.ZERO


func _prepare_query(ball: PinballBall, swings: Array[PinballFlipper.Swing]) -> void:
	_query.shape = (ball.get_node("CollisionShape2D") as CollisionShape2D).shape
	_query.collision_mask = ball.solid_collision_mask()
	var ball_rid := ball.get_rid()
	var changed := _ball_rid != ball_rid or _excluded.size() != swings.size() + 1
	if not changed:
		for index: int in swings.size():
			if _excluded[index + 1] != swings[index].flipper.get_rid():
				changed = true
				break
	if changed:
		_ball_rid = ball_rid
		_excluded.clear()
		_excluded.append(ball_rid)
		for swing: PinballFlipper.Swing in swings:
			_excluded.append(swing.flipper.get_rid())
		_query.exclude = _excluded
