extends "res://experiments/flippers/tests/native_motion.gd"

const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")

var refined: bool = false
var detection_us: int = 0
var sweep_queries: int = 0
var extra_checks: int = 0


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	var sources := RefinedMotion.plans_for(swings, 4) if refined else swings
	var measured: Array[PinballFlipper.Swing] = []
	for source: PinballFlipper.Swing in sources:
		var plan := Probe.new()
		plan.source = source
		for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
			plan.set(property, source.get(property))
		measured.append(plan)
	super.advance(delta, measured)
	detection_us = 0
	sweep_queries = 0
	extra_checks = 0
	for plan: Probe in measured:
		detection_us += plan.total_us
		sweep_queries += plan.queries
		if refined:
			extra_checks += int(plan.source.get("extra_checks"))


class Probe extends PinballFlipper.Swing:
	var source: PinballFlipper.Swing
	var total_us: int = 0
	var queries: int = 0


	func sweep(
		center: Vector2, velocity: Vector2, radius: float, elapsed: float,
		duration: float, equalization: float, accept: Callable = Callable(),
	) -> Dictionary:
		var began := Time.get_ticks_usec()
		var hit := source.sweep(center, velocity, radius, elapsed, duration, equalization, accept)
		total_us += Time.get_ticks_usec() - began
		queries += 1
		return hit
