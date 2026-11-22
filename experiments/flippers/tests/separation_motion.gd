extends "res://experiments/flippers/tests/shot_motion.gd"

const Surroundings = preload("res://experiments/flippers/tests/separation_environment.gd")

var _observer: Surroundings = Surroundings.new()
var _environment: Dictionary = {}
var _history: Dictionary = {}
var _velocity_history: Dictionary = {}
var _tick_start: Vector2
var _native_start_contact: Dictionary = {}
var _native_geometry: Dictionary = {}


static func state_class(initial: bool, start_contact: bool, released: bool) -> String:
	return "D" if released and initial else ("B" if initial else ("C" if start_contact else "A"))


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	assert(not split_budgets, "This audit keeps the shared contact budget at eight")
	_history.clear()
	_velocity_history.clear()
	_environment = {}
	_tick_start = body.global_position
	super.advance(delta, swings)


func contact_separation(hit: Dictionary) -> Vector2:
	var offset := super.contact_separation(hit)
	_environment = _observer.observe(body, radius, hit.flipper,
		body.global_position + body.velocity * float(hit.time), offset,
		flippers, _plans, _elapsed)
	return offset


func _native_contact(collision: KinematicCollision2D) -> void:
	var remaining := maxf(0.0, _duration - _elapsed)
	var motion := body.velocity * remaining
	var fraction := 0.0
	if motion.length_squared() > 0.000001:
		fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)
	var time := _elapsed + remaining * fraction
	var start := _previous_position + body.velocity * (time - _elapsed)
	_environment = _observer.observe(body, radius, collision.get_collider(), start,
		body.global_position - start, flippers, _plans, time)
	_native_start_contact = {}
	_native_geometry = {}
	var item := collision.get_collider() as PinballFlipper
	if item != null:
		_native_start_contact = item._contact_at(_previous_position,
			radius, _pose_at(item, _elapsed), 0.0, 0.0)
		var pose := _pose_at(item, time)
		var before := item._contact_at(start, radius, pose, 0.0, 0.0)
		var after := item._contact_at(body.global_position, radius, pose, 0.0, 0.0)
		_native_geometry = {"geometric_contact_found": not before.is_empty(),
			"geometric_contact_depth_px": before.get("depth", 0.0),
			"post_separation_overlap": not after.is_empty(),
			"post_separation_depth_px": after.get("depth", 0.0)}
	super._native_contact(collision)


func _record_event(hit: Dictionary, incoming: Vector2, shot: bool) -> void:
	super._record_event(hit, incoming, shot)
	var event: Dictionary = events.back()
	event["environment"] = _environment.duplicate(true)
	if event.kind == "native":
		event.merge(_native_geometry, true)
	else:
		event["geometric_contact_found"] = true
		event["geometric_contact_depth_px"] = event.get("depth_px", 0.0)
	var item: PinballFlipper = hit.get("flipper")
	if item == null or not _context.has("tick_initial_overlap"):
		event["state_class"] = "other"
		return
	var id := item.get_instance_id()
	var initial_hit := item._contact_at(_tick_start, radius, _pose_at(item, 0.0), 0.0, 0.0)
	var initial: bool = _context.tick_initial_overlap
	var start_contact: bool = _context.get("query_start_overlap", not _native_start_contact.is_empty())
	var depth: float = _context.get("query_start_depth_px", _native_start_contact.get("depth", 0.0))
	event["state_class"] = state_class(initial, start_contact, guard_released)
	event["tick_initial_depth_px"] = initial_hit.get("depth", 0.0)
	event["query_start_contact"] = start_contact
	event["query_start_depth_px"] = depth
	event["positive_query_start_depth"] = start_contact and depth > 0.0
	event["same_flipper_contact_before"] = _history.get(id, 0) > 0
	event["same_flipper_contact_count_before"] = _history.get(id, 0)
	event["same_flipper_velocity_change_before"] = _velocity_history.get(id, false)
	_history[id] = _history.get(id, 0) + 1
	_velocity_history[id] = _velocity_history.get(id, false) or event.changed
