extends "res://experiments/flippers/preview_ball.gd"

var shots: int = 0
var forbidden_contacts: int = 0
var contact_limit_steps: int = 0
var other_contacts: int = 0
var max_step_contacts: int = 0
var last_native_contact: Dictionary = {}
var native_contacts_this_step: int = 0
var capped_sources: Dictionary[String, int] = {}
var first_cap: Dictionary = {}
var truncated_steps: int = 0
var discarded_seconds: float = 0.0
var max_discarded_seconds: float = 0.0
var _step_contacts: int = 0
var _step_sources: Array[String] = []
var _used_seconds: float = 0.0
var _step_seconds: float = 0.0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	_step_contacts = 0
	native_contacts_this_step = 0
	_used_seconds = 0.0
	_step_seconds = delta
	_step_sources.clear()
	var start_position := global_position
	var start_velocity := velocity
	super.advance(delta, swings)
	max_step_contacts = maxi(max_step_contacts, _step_contacts)
	if _step_contacts >= MAX_CONTACTS:
		contact_limit_steps += 1
		var discarded := maxf(0.0, delta - _used_seconds)
		if discarded >= 0.000001:
			truncated_steps += 1
			discarded_seconds += discarded
			max_discarded_seconds = maxf(max_discarded_seconds, discarded)
		for source: String in _step_sources:
			capped_sources[source] = capped_sources.get(source, 0) + 1
		if first_cap.is_empty():
			first_cap = {"start_position": start_position, "end_position": global_position,
				"start_velocity": start_velocity, "end_velocity": velocity,
				"sources": _step_sources.duplicate(), "discarded_seconds": discarded}


func _apply_swept_contact(hit: Dictionary) -> void:
	_step_contacts += 1
	_used_seconds += hit.time
	_step_sources.append("sweep:" + hit.flipper.name)
	if (flippers as ShotGuard).is_suppressed(self):
		forbidden_contacts += 1
	super._apply_swept_contact(hit)


func _resolve_contact(collision: KinematicCollision2D) -> void:
	var remaining := _step_seconds - _used_seconds
	# The base ball treats very short motion as zero collision time; use the
	# same cutoff so the diagnostic does not count discarded time as consumed.
	if (velocity * remaining).length_squared() > 0.000001:
		_used_seconds += clampf(collision.get_travel().dot(velocity) / velocity.length_squared(),
			0.0, remaining)
	last_native_contact = {"collider": collision.get_collider().name,
		"normal": collision.get_normal(), "point": collision.get_position()}
	_step_contacts += 1
	native_contacts_this_step += 1
	_step_sources.append(collision.get_collider().name)
	if collision.get_collider() is PinballFlipper:
		if (flippers as ShotGuard).is_suppressed(self):
			forbidden_contacts += 1
	else:
		other_contacts += 1
	super._resolve_contact(collision)


func _start_guard(elapsed: float) -> void:
	shots += 1
	super._start_guard(elapsed)
