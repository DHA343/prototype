extends PinballMotion

# Experimental: any unresolved search invalidates the step; no fallback is hidden here.

const Continuous = preload("res://experiments/flippers/continuous_swing.gd")

var evaluations: int = 0
var unresolved: int = 0


static func plans_for(sources: Array[PinballFlipper.Swing]) -> Array[PinballFlipper.Swing]:
	var plans: Array[PinballFlipper.Swing] = []
	for source: PinballFlipper.Swing in sources:
		var plan := Continuous.new()
		for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
			plan.set(property, source.get(property))
		plans.append(plan)
	return plans


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var plans := plans_for(swings)
	super.advance(delta, plans)
	evaluations = 0
	unresolved = 0
	for plan: Continuous in plans:
		evaluations += plan.evaluations
		unresolved += plan.unresolved
