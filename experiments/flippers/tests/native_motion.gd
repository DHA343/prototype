extends PinballMotion

const Counter = preload("res://experiments/flippers/tests/native_flipper.gd")

var events: Array[Dictionary] = []
var native_queries: int = 0
var discarded_seconds: float = 0.0
var native_response: Callable
var _duration: float = 0.0
var _elapsed: float = 0.0
var _previous_position: Vector2
var _kind: String = ""
var _correction: Vector2
var _target: String = ""


func _init(target: CharacterBody2D) -> void:
	super(target)
	separate_new_contacts = false
	native_contact = _native_contact


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	begin(delta)
	super.advance(delta, swings)
	var remaining := maxf(0.0, delta - _elapsed)
	discarded_seconds = remaining if events.size() == MAX_CONTACTS else 0.0
	native_queries = events.size() + int(events.size() < MAX_CONTACTS and remaining >= 0.000001)


func begin(delta: float) -> void:
	events.clear()
	native_queries = 0
	discarded_seconds = 0.0
	_duration = delta
	_elapsed = 0.0
	_previous_position = body.global_position
	_correction = Vector2.ZERO


func apply_swept_contact(hit: Dictionary) -> void:
	_elapsed += hit.time
	_kind = "sweep"
	_target = str(hit.flipper.name)
	super.apply_swept_contact(hit)
	_previous_position = body.global_position


func contact_separation(hit: Dictionary) -> Vector2:
	var counted := hit.flipper as Counter
	if counted != null:
		counted.separating = true
	var offset := super.contact_separation(hit)
	if counted != null:
		counted.separating = false
	_correction = offset
	return offset


func _native_contact(collision: KinematicCollision2D) -> void:
	var incoming := body.velocity
	var motion := incoming * maxf(0.0, _duration - _elapsed)
	var fraction := 0.0
	if motion.length_squared() > 0.000001:
		fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)
	var time := (_duration - _elapsed) * fraction
	_elapsed += time
	_kind = "native"
	_target = str(collision.get_collider().name)
	_correction = body.global_position - (_previous_position + incoming * time)
	var count := events.size()
	if native_response.is_valid():
		native_response.call(collision)
	else:
		super.resolve_contact(collision)
	if events.size() == count:
		_record_event({"point": collision.get_position(), "normal": collision.get_normal(),
			"ratio": 0.0}, incoming, false)
	_previous_position = body.global_position


func _respond_to_flipper(hit: Dictionary) -> void:
	var incoming := body.velocity
	var speed := -(incoming - (hit.surface_velocity as Vector2)).dot(hit.normal)
	var shot: bool = speed > 0.0 and hit.is_striking
	super._respond_to_flipper(hit)
	_record_event(hit, incoming, shot)


func _record_event(hit: Dictionary, incoming: Vector2, shot: bool) -> void:
	var outgoing := body.velocity.limit_length(max_speed)
	events.append({"found": true, "kind": _kind, "target": _target, "time_ms": _elapsed * 1000.0,
		"point": _vec(hit.point), "normal": _vec(hit.normal), "ratio": hit.ratio,
		"shot": shot, "changed": incoming.distance_to(outgoing) > 0.01,
		"velocity": _vec(outgoing), "speed": outgoing.length(),
		"correction_px": _correction.length(), "position": _vec(body.global_position),
		"end": _vec(body.global_position + outgoing * maxf(0.0, _duration - _elapsed))})


static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]
