extends PinballMotion

const Refined = preload("res://experiments/flippers/refined_swing.gd")

var iterations: int = 4


static func plans_for(sources: Array[PinballFlipper.Swing], count: int) -> Array[PinballFlipper.Swing]:
	var plans: Array[PinballFlipper.Swing] = []
	for source: PinballFlipper.Swing in sources:
		var plan := Refined.new()
		for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
			plan.set(property, source.get(property))
		plan.iterations = count
		plans.append(plan)
	return plans


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	super.advance(delta, plans_for(swings, iterations))
