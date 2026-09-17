class_name ScaleSpring
extends RefCounted

const EQUILIBRIUM: float = 1.0
const MAX_STEP: float = 0.008
const MAX_SUBSTEPS: int = 8

var stiffness: float = 200.0
var damping: float = 10.0
var settle_distance: float = 0.001
var settle_velocity: float = 0.01
var max_velocity: float = 10.0

var value: float = EQUILIBRIUM
var velocity: float = 0.0


func start(initial_value: float) -> void:
	value = initial_value
	velocity = 0.0


func add_impulse(amount: float) -> void:
	velocity += amount
	_clamp_velocity()


func update(delta: float) -> void:
	var remaining_time := minf(maxf(delta, 0.0), MAX_STEP * MAX_SUBSTEPS)
	while remaining_time > 0.0:
		var step := minf(remaining_time, MAX_STEP)
		var acceleration := (
			-stiffness * (value - EQUILIBRIUM)
			- damping * velocity
		)

		velocity += acceleration * step
		_clamp_velocity()
		value += velocity * step

		remaining_time -= step


func settle() -> void:
	value = EQUILIBRIUM
	velocity = 0.0


func is_settled() -> bool:
	return (
		absf(value - EQUILIBRIUM) <= settle_distance
		and absf(velocity) <= settle_velocity
	)


func _clamp_velocity() -> void:
	var velocity_limit := maxf(max_velocity, 0.0)
	velocity = clampf(velocity, -velocity_limit, velocity_limit)
