extends "res://experiments/flippers/tests/native_motion.gd"

const QuadMotion = preload("res://experiments/flippers/quad_motion.gd")
const Continuous = preload("res://experiments/flippers/continuous_swing.gd")

var evaluations: int = 0
var unresolved: int = 0
var reasons: Array[String] = []
var details: Array[Dictionary] = []


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var plans := QuadMotion.plans_for(swings)
	super.advance(delta, plans)
	evaluations = 0
	unresolved = 0
	reasons.clear()
	details.clear()
	for plan: Continuous in plans:
		evaluations += plan.evaluations
		unresolved += plan.unresolved
		if plan.unresolved > 0:
			reasons.append(plan.unresolved_reason)
			details.append(plan.unresolved_context.duplicate(true))
