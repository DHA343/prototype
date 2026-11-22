extends "res://experiments/flippers/tests/release_motion.gd"

const CausalRelease = preload("res://experiments/flippers/tests/causal_release.gd")

var stages: Array[Dictionary] = []
var native_geometry: Array[Dictionary] = []
var query_raw_fraction: bool = false


func _init(target: CharacterBody2D) -> void:
	super(target)
	recovery = CausalRelease.new()


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	stages.clear()
	native_geometry.clear()
	super.advance(delta, swings)


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	stages.append({"stage": "3_detection_start", "position": _vec(body.global_position),
		"velocity": _vec(body.velocity), "guard": flippers.is_target_disabled(body.get_instance_id()),
		"exceptions": body.get_collision_exceptions().map(func(item: PhysicsBody2D) -> String: return str(item.name)),
		"time_ms": 0.0, "remaining_ms": delta * 1000.0})
	super.advance_motion(delta, swings)


func apply_swept_contact(hit: Dictionary) -> void:
	stages.append({"stage": "3_custom_detection", "iteration": events.size(),
		"position": _vec(body.global_position), "velocity": _vec(body.velocity),
		"target": str(hit.flipper.name), "point": _vec(hit.point), "normal": _vec(hit.normal),
		"depth_px": hit.depth, "time_ms": (_elapsed + hit.time) * 1000.0,
		"remaining_ms": (_duration - _elapsed - hit.time) * 1000.0})
	super.apply_swept_contact(hit)
	stages.append({"stage": "6_resume", "iteration": events.size(), "position": _vec(body.global_position),
		"velocity": _vec(body.velocity), "time_ms": _elapsed * 1000.0,
		"remaining_ms": maxf(0.0, _duration - _elapsed) * 1000.0})


func contact_separation(hit: Dictionary) -> Vector2:
	var offset := super.contact_separation(hit)
	stages.append({"stage": "4_custom_correction", "iteration": events.size(),
		"before": _vec(body.global_position + body.velocity * float(hit.time)), "offset": _vec(offset),
		"distance_px": offset.length(), "target": str(hit.flipper.name),
		"policy": _context.separation_policy, "tick_start_contact": _context.tick_initial_overlap,
		"segment_start_contact": _context.query_start_overlap, "depth_px": hit.depth,
		"normal_exit_estimate_px": maxf(0.0, hit.depth) + SEPARATION_MARGIN,
		"after_contact": _context.post_separation_overlap, "environment": _environment.duplicate(true),
		"time_ms": _elapsed * 1000.0, "remaining_ms": (_duration - _elapsed) * 1000.0})
	return offset


func _respond_to_flipper(hit: Dictionary) -> void:
	var before := body.velocity
	super._respond_to_flipper(hit)
	stages.append({"stage": "5_flipper_response", "iteration": events.size() - 1,
		"position": _vec(body.global_position), "incoming": _vec(before),
		"outgoing": _vec(body.velocity.limit_length(max_speed)), "changed": events.back().changed,
		"time_ms": _elapsed * 1000.0, "remaining_ms": (_duration - _elapsed) * 1000.0})


func _native_contact(collision: KinematicCollision2D) -> void:
	var requested := body.velocity * maxf(0.0, _duration - _elapsed)
	var actor := collision.get_collider() as PhysicsBody2D
	var surface: Vector2 = actor.velocity if actor is Enemy else Vector2.ZERO
	var entry := {"stage": "4_godot_recovery", "iteration": events.size(),
		"target": str(collision.get_collider().name), "point": _vec(collision.get_position()),
		"normal": _vec(collision.get_normal()), "reported_depth_px": collision.get_depth(),
		"query_start": _vec(_previous_position), "position_after_query": _vec(body.global_position),
		"incoming": _vec(body.velocity), "requested_motion": _vec(requested),
		"travel": _vec(collision.get_travel()), "remainder": _vec(collision.get_remainder()),
		"travel_plus_remainder_minus_motion": _vec(collision.get_travel() + collision.get_remainder() - requested),
		"surface_velocity": _vec(surface),
		"relative_normal_before": (body.velocity - surface).dot(collision.get_normal()),
		"static_normal_before": body.velocity.dot(collision.get_normal()),
		"geometry_before_depth_px": _depth(actor, _previous_position),
		"geometry_after_depth_px": _depth(actor, body.global_position),
		"before_time_ms": _elapsed * 1000.0}
	if query_raw_fraction:
		var parameters := PhysicsTestMotionParameters2D.new()
		parameters.from = body.global_transform
		parameters.from.origin = _previous_position
		parameters.motion = requested
		parameters.margin = CONTACT_MARGIN
		parameters.recovery_as_collision = true
		var raw := PhysicsTestMotionResult2D.new()
		var found := PhysicsServer2D.body_test_motion(body.get_rid(), parameters, raw)
		entry["raw_query"] = {"found": found, "safe_fraction": raw.get_collision_safe_fraction(),
			"unsafe_fraction": raw.get_collision_unsafe_fraction(), "travel": _vec(raw.get_travel()),
			"remainder": _vec(raw.get_remainder()),
			"same_collider": found and raw.get_collider_rid() == collision.get_collider_rid()}
	stages.append(entry)
	super._native_contact(collision)
	entry["outgoing"] = _vec(body.velocity.limit_length(max_speed))
	entry["time_ms"] = _elapsed * 1000.0
	entry["remaining_ms"] = maxf(0.0, _duration - _elapsed) * 1000.0
	native_geometry.append(entry)
	stages.append({"stage": "6_native_resume", "position": _vec(body.global_position),
		"velocity": _vec(body.velocity.limit_length(max_speed)), "time_ms": _elapsed * 1000.0,
		"remaining_ms": maxf(0.0, _duration - _elapsed) * 1000.0})


func _depth(actor: PhysicsBody2D, center: Vector2) -> float:
	if actor is Enemy or actor is PinballBumper:
		return maxf(0.0, radius + actor.radius - center.distance_to(actor.global_position))
	if actor is PinballFlipper:
		return actor._contact_at(center, radius, actor.global_transform, 0.0, 0.0).get("depth", 0.0)
	var collision := actor.get_child(0) as CollisionShape2D
	var segments := collision.shape as ConcavePolygonShape2D
	var closest := INF
	if segments != null:
		for index: int in range(0, segments.segments.size(), 2):
			var point := Geometry2D.get_closest_point_to_segment(center,
				collision.to_global(segments.segments[index]), collision.to_global(segments.segments[index + 1]))
			closest = minf(closest, point.distance_to(center))
	return maxf(0.0, radius - closest)
