extends PinballFlipper.Swing

var iterations: int = 4
var coarse_checks: int = 0
var extra_checks: int = 0
var eligible: int = 0
var refined: int = 0
var no_previous: int = 0
var previous_contact: int = 0
var final_invalid: int = 0
var stopped_state: int = 0


func _sample(
	center: Vector2, velocity: Vector2, radius: float, elapsed: float,
	duration: float, omega: float, equalization: float, accept: Callable,
) -> Dictionary:
	var travel := (velocity.length() + absf(omega) * reach) * duration
	var samples := maxi(1, ceili(travel / PinballFlipper.SWEEP_STEP))
	var last_time := 0.0
	var last_contact := false
	for index in range(samples + 1 if duration > 0.0 else 1):
		var time := duration * float(index) / samples
		coarse_checks += 1
		var hit := _contact(center, velocity, radius, elapsed, time, omega, equalization)
		var geometry_contact := not hit.is_empty()
		if geometry_contact and (not accept.is_valid() or accept.call(hit)):
			if hit.depth > 0.01 or (velocity - (hit.surface_velocity as Vector2)).dot(hit.normal) < 0.0:
				if index == 0:
					no_previous += 1
				elif last_contact:
					previous_contact += 1
				else:
					eligible += 1
					if iterations > 0:
						var candidate := _refine(center, velocity, radius, elapsed,
							last_time, time, omega, equalization)
						if candidate.is_empty() or (accept.is_valid() and not accept.call(candidate)):
							final_invalid += 1
						else:
							refined += 1
							return candidate
				hit.time = time
				hit.flipper = flipper
				return hit
		last_time = time
		last_contact = geometry_contact
	return {}


func _refine(
	center: Vector2, velocity: Vector2, radius: float, elapsed: float,
	low: float, high: float, omega: float, equalization: float,
) -> Dictionary:
	# The coarse scan already proved low is geometrically clear and high overlaps.
	for iteration in iterations:
		var middle := (low + high) * 0.5
		extra_checks += 1
		if _contact(center, velocity, radius, elapsed, middle, omega, equalization).is_empty():
			low = middle
		else:
			high = middle
	var actual_omega := speed if elapsed + high < stop_time else 0.0
	stopped_state += int(actual_omega != omega)
	extra_checks += 1
	var hit := _contact(center, velocity, radius, elapsed, high, actual_omega, equalization)
	if not hit.is_empty():
		hit.time = high
		hit.flipper = flipper
	return hit


func _contact(
	center: Vector2, velocity: Vector2, radius: float,
	elapsed: float, time: float, omega: float, equalization: float,
) -> Dictionary:
	var pose := parent_pose * Transform2D(
		start_angle + speed * minf(elapsed + time, stop_time), flipper.position)
	return flipper._contact_at(center + velocity * time, radius, pose, omega, equalization)
