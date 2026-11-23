extends "res://experiments/flippers/tests/value_motion.gd"

const Convex = preload("res://experiments/flippers/tests/value_reference.gd")
const ExitGuard = preload("res://experiments/flippers/tests/guard_exit.gd")

var tick: Dictionary = {}
var clock_frame: int = 0
var same_tick_descent: bool = false
var _source_plans: Array[PinballFlipper.Swing] = []


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_source_plans = swings
	var manager := flippers as ExitGuard
	manager.sampled_id = body.get_instance_id()
	# ValueMotion fills this same dictionary before the parent calls refresh_target().
	manager.initial_contacts = _initial
	normal_new = true
	audit_detection = false
	tick = {"frame": clock_frame, "position_before": _vec(body.global_position),
		"velocity_before": _vec(body.velocity), "next_velocity": _vec(step_velocity(body.velocity, delta)),
		"guard_before": flippers.is_target_disabled(body.get_instance_id()),
		"start_gap": _gaps(body.global_position, 0.0),
		"board_only_gap": _gaps(body.global_position, delta), "duration": delta}
	if not swings.is_empty() and _near_board(delta):
		tick["before_ball"] = _snapshot()
	super.advance(delta, swings)
	tick["position_after"] = _vec(body.global_position)
	tick["velocity_after"] = _vec(body.velocity)
	tick["end_gap"] = _gaps(body.global_position, delta)
	tick["ball_only_gap"] = _gaps(body.global_position, 0.0)
	tick["guard_after"] = flippers.is_target_disabled(body.get_instance_id())
	tick["contacts"] = events.duplicate(true)
	tick["cap"] = cap
	tick["unexecuted_path_ms"] = discarded_true_s * 1000


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	tick["guard_after_refresh"] = flippers.is_target_disabled(body.get_instance_id())
	super.advance_motion(delta, swings)


func _capture(point: Vector2, normal: Vector2, incoming: Vector2, shot: bool, actor: PhysicsBody2D) -> void:
	super._capture(point, normal, incoming, shot, actor)
	var event: Dictionary = events.back()
	event["actor_kind"] = "enemy" if actor is Enemy else ("flipper" if actor is PinballFlipper else "world")
	event["guard"] = flippers.is_target_disabled(body.get_instance_id())
	event["gap"] = _gaps(body.global_position, _legacy)
	event["gap_before_correction"] = _gaps(body.global_position - _offset, _legacy)
	if actor is PinballFlipper: event["side"] = actor.side
	if actor is Enemy: event["surface_velocity"] = _vec(actor.velocity)


func _exclude_flippers() -> void:
	if not same_tick_descent:
		super._exclude_flippers()
		return
	# Keep rotating plans in B's active list even while the guard gates their tests.
	# Static plates still use the original temporary Godot exceptions.
	for item: PinballFlipper in flippers.items:
		var moving := _source_plans.any(func(plan: PinballFlipper.Swing) -> bool: return plan.flipper == item)
		if not moving and item not in body.get_collision_exceptions():
			body.add_collision_exception_with(item)
			_guard_exceptions.append(item)


func _native_contact(collision: KinematicCollision2D) -> void:
	super._native_contact(collision)
	if not same_tick_descent or collision.get_collider() is PinballFlipper \
			or not flippers.is_target_disabled(body.get_instance_id()) or body.velocity.y <= 1.0:
		return
	var gaps := _gaps(body.global_position, _legacy)
	if gaps[0] <= 0.0 or gaps[1] <= 0.0: return
	flippers.refresh_target(body, body.velocity.y)
	for item: PinballFlipper in _guard_exceptions:
		body.remove_collision_exception_with(item)
	_guard_exceptions.clear()
	events.back()["guard_released_after_external"] = true
	events.back()["release_gap"] = gaps


func _gaps(position: Vector2, time: float) -> Array[float]:
	var result: Array[float] = []
	for item: PinballFlipper in flippers.items:
		var pose := item.global_transform
		for plan: PinballFlipper.Swing in _source_plans:
			if plan.flipper == item:
				pose = plan.parent_pose * Transform2D(
					plan.start_angle + plan.speed * minf(time, plan.stop_time), item.position)
		result.append(Convex.gap(position, radius, (item as TableFlipper).world_polygon_at(pose)))
	return result


func _near_board(delta: float) -> bool:
	for plan: PinballFlipper.Swing in _source_plans:
		if body.global_position.distance_to(plan.origin) <= plan.reach + radius + body.velocity.length() * delta:
			return true
	return false


func _snapshot() -> Dictionary:
	var actors: Array[Dictionary] = []
	for node: Node in body.get_tree().get_nodes_in_group("enemies"):
		var actor := node as Enemy
		if actor == null or not actor.active: continue
		actors.append({"position": _vec(actor.global_position), "velocity": _vec(actor.velocity),
			"movement": _vec(actor._movement_velocity), "knockback": _vec(actor._knockback_initial),
			"knockback_elapsed": actor._knockback_elapsed, "crowd": _vec(actor.crowd_motion),
			"health": actor.current_health, "radius": actor.radius, "layer": actor.collision_layer,
			"spawn_elapsed": actor._spawn_elapsed,
			"ball_contact_blocked": actor in (body as PinballBall)._enemy_contacts})
	var offsets: Array[float] = []
	for item: PinballFlipper in flippers.items:
		var offset := item._offset
		for plan: PinballFlipper.Swing in _source_plans:
			if plan.flipper == item: offset = plan.start_angle - item._rest_rotation
		offsets.append(offset)
	return {"position": _vec(body.global_position), "velocity": _vec(body.velocity),
		"guard": flippers.is_target_disabled(body.get_instance_id()), "offsets": offsets,
		"enemies": actors, "phase": "Enemy already moved; flipper offsets are tick-start"}
