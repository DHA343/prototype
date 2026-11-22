extends "res://experiments/flippers/separation.gd"

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
		super.advance_motion(delta, swings)
