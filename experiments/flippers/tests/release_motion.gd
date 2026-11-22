extends "res://experiments/flippers/tests/separation_motion.gd"

const Recovery = preload("res://experiments/flippers/release.gd")

var recovery: Recovery = Recovery.new()


func reset() -> void:
	super.reset()
	recovery.reset()


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	recovery.begin(body, radius, flippers, swings, delta)
	super.advance(delta, swings)


func advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	if not recovery.failed:
		_previous_position = body.global_position
		super.advance_motion(delta, swings)


func _record_event(hit: Dictionary, incoming: Vector2, shot: bool) -> void:
	super._record_event(hit, incoming, shot)
	events.back()["release_requested"] = recovery.tick.get("requested", false)
	events.back()["guard_released"] = recovery.tick.get("released", false)
