extends "res://experiments/flippers/tests/multiball_probe.gd"

var suppression_enabled: bool = true
var simulation_time: float = 0.0
var first_shot: Dictionary = {}
var opposite_normal_changes: Array[Dictionary] = []
var opposite_shots: Array[Dictionary] = []
var opposite_corrections: int = 0
var external_since_shot: int = 0
var cap_trace: Array[Dictionary] = []
var embedded_releases: Array[Dictionary] = []
var _trace: Array[Dictionary] = []
var _contact_flipper: PinballFlipper


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_trace.clear()
	var releases_before := embedded_releases.size()
	var shots_before := shots
	if suppression_enabled and (flippers as ShotGuard).is_suppressed(self) \
		and step_velocity(velocity, delta).y > ShotGuard.DESCENT_SPEED:
		for item: PinballFlipper in flippers.items:
			var contact := item._contact_at(global_position, radius, item.global_transform, 0, 0)
			if not contact.is_empty():
				embedded_releases.append({"time": simulation_time, "side": item.side,
					"depth": contact.depth, "position": _vector(global_position),
					"velocity_before": _vector(velocity),
					"step_velocity": _vector(step_velocity(velocity, delta))})
	super.advance(delta, swings)
	for index in range(releases_before, embedded_releases.size()):
		embedded_releases[index].after_position = _vector(global_position)
		embedded_releases[index].after_velocity = _vector(velocity)
		embedded_releases[index].new_shots = shots - shots_before
	if _step_contacts >= MAX_CONTACTS and cap_trace.is_empty():
		cap_trace = _trace.duplicate(true)


func _apply_swept_contact(hit: Dictionary) -> void:
	_contact_flipper = hit.flipper
	var before := velocity
	var shot_count_before := shots
	var position_before := global_position
	_trace.append({"kind": "sweep", "collider": _contact_flipper.name,
		"time": hit.time, "incoming": -(before - hit.surface_velocity).dot(hit.normal),
		"depth": hit.depth})
	super._apply_swept_contact(hit)
	_record_opposite(before, shot_count_before, hit.normal,
		global_position.distance_to(position_before + before * hit.time), "sweep")


func _resolve_contact(collision: KinematicCollision2D) -> void:
	_contact_flipper = collision.get_collider() as PinballFlipper
	var before := velocity
	var shot_count_before := shots
	var remaining := _step_seconds - _used_seconds
	var surface := Vector2.ZERO
	if _contact_flipper != null:
		surface = _contact_flipper.surface_velocity_at(collision.get_position())
	_trace.append({"kind": "native", "collider": collision.get_collider().name,
		"incoming": -(before - surface).dot(collision.get_normal()),
		"remaining": remaining, "motion_squared": (before * remaining).length_squared(),
		"travel": _vector(collision.get_travel()), "normal": _vector(collision.get_normal()),
		"velocity": _vector(before)})
	super._resolve_contact(collision)
	if _contact_flipper == null:
		if not first_shot.is_empty():
			external_since_shot += 1
	else:
		_record_opposite(before, shot_count_before, collision.get_normal(), 0.0, "native")


func _start_guard(elapsed: float) -> void:
	if first_shot.is_empty():
		first_shot = {"side": _contact_flipper.side, "velocity": _vector(velocity),
			"position": _vector(global_position), "time": simulation_time + _used_seconds,
			"angle": rad_to_deg(Vector2.UP.angle_to(velocity))}
	if suppression_enabled:
		super._start_guard(elapsed)
	else:
		shots += 1
		(flippers as ShotGuard).shot_count += 1


func _record_opposite(
	before: Vector2, shots_before: int, normal: Vector2, correction: float, kind: String,
) -> void:
	if first_shot.is_empty() or _contact_flipper.side == first_shot.side:
		return
	# Isolate immediate interference before any wall contact or descending return.
	if external_since_shot > 0 or before.y >= -1.0:
		return
	var event := {"kind": kind, "side": _contact_flipper.side,
		"time": simulation_time + _used_seconds, "before": _vector(before),
		"after": _vector(velocity), "normal": _vector(normal), "position": _vector(global_position),
		"angle_before": rad_to_deg(Vector2.UP.angle_to(before)),
		"angle_after": rad_to_deg(Vector2.UP.angle_to(velocity)),
		"change_degrees": absf(rad_to_deg(before.angle_to(velocity)))}
	if shots > shots_before:
		opposite_shots.append(event)
	elif velocity.distance_to(before) > 0.01:
		event.more_vertical = velocity.y < 0 \
			and absf(event.angle_after) < absf(event.angle_before) - 1.0
		opposite_normal_changes.append(event)
	elif correction > 0.1:
		opposite_corrections += 1


static func _vector(value: Vector2) -> Array[float]:
	return [value.x, value.y]
