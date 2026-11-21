extends "res://experiments/flippers/tests/native_motion.gd"

const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")
const Refined = preload("res://experiments/flippers/refined_swing.gd")

var iterations: int = 4
var search_counts: Dictionary = {}


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var plans := RefinedMotion.plans_for(swings, iterations)
	super.advance(delta, plans)
	search_counts = {}
	for plan: Refined in plans:
		for key: String in ["coarse_checks", "extra_checks", "eligible", "refined", "no_previous",
			"previous_contact", "final_invalid", "stopped_state"]:
			search_counts[key] = search_counts.get(key, 0) + int(plan.get(key))
