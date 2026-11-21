extends PinballFlipper.Swing

const Quad = preload("res://experiments/flippers/quad_contact.gd")

var evaluations: int = 0


func _sample(
	center: Vector2, velocity: Vector2, radius: float, elapsed: float,
	duration: float, omega: float, equalization: float, accept: Callable,
) -> Dictionary:
	var travel := (velocity.length() + absf(omega) * reach) * duration
	var samples := maxi(1, ceili(travel / PinballFlipper.SWEEP_STEP))
	for index in range(samples + 1 if duration > 0.0 else 1):
		var time := duration * float(index) / samples
		var at := elapsed + time
		var pose := parent_pose * Transform2D(start_angle + speed * minf(at, stop_time), flipper.position)
		evaluations += 1
		var hit := Quad.contact(flipper, center + velocity * time, radius, pose, omega, equalization)
		if hit.is_empty() or (accept.is_valid() and not accept.call(hit)):
			continue
		if hit.depth > 0.01 or (velocity - (hit.surface_velocity as Vector2)).dot(hit.normal) < 0.0:
			hit.time = time
			hit.flipper = flipper
			return hit
	return {}
