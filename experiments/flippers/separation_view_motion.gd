extends "res://experiments/flippers/tests/value_motion.gd"

const Geometry = preload("res://experiments/flippers/tests/value_geometry.gd")

var _view: Dictionary = {}


func apply_swept_contact(hit: Dictionary) -> void:
	var initial: bool = _initial.get(hit.flipper.get_instance_id(), false)
	var releasing := released_inside.any(func(row: Dictionary) -> bool:
		return row.target == str(hit.flipper.name))
	_view = {"depth_px": hit.depth, "depth_kind": "幾何", "category":
		"③解除時の重なり" if initial and releasing else ("開始重なり" if initial else "新接触／再接触")}
	super.apply_swept_contact(hit)


func _native_contact(collision: KinematicCollision2D) -> void:
	var actor := collision.get_collider() as PhysicsBody2D
	var depth := Geometry.depth(actor, _previous, radius)
	_view = {"depth_px": depth, "depth_kind": "区間開始の幾何",
		"reported_depth_px": collision.get_depth(), "category": "標準接触／回復"}
	if actor is PinballFlipper and not released_inside.is_empty():
		_view.category = "③解除＋標準接触／回復"
	super._native_contact(collision)


func _capture(point: Vector2, normal: Vector2, incoming: Vector2, shot: bool, actor: PhysicsBody2D) -> void:
	super._capture(point, normal, incoming, shot, actor)
	var event: Dictionary = events.back()
	event.merge(_view, true)
	event["correction_start"] = _vec(body.global_position - _offset)
	event["correction_end"] = _vec(body.global_position)
	if event.new_contact: event.category = "新接触（両開始時とも非接触）"
	if event.has("environment"):
		for other: Dictionary in event.environment.introduced:
			var target := instance_from_id(int(other.id)) as PhysicsBody2D
			if is_instance_valid(target):
				other["depth_px"] = Geometry.depth(target, body.global_position, radius)
