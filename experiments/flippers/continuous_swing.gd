extends PinballFlipper.Swing

const Quad = preload("res://experiments/flippers/quad_contact.gd")
const GAP_TOLERANCE: float = 0.0005
const MAX_SEARCH: int = 2048

var evaluations: int = 0
var unresolved: int = 0
var unresolved_reason: String = ""
var unresolved_context: Dictionary = {}


func sweep(
	center: Vector2, velocity: Vector2, radius: float,
	elapsed: float, duration: float, equalization: float, accept: Callable = Callable(),
) -> Dictionary:
	var before := unresolved
	var hit := super.sweep(center, velocity, radius, elapsed, duration, equalization, accept)
	return {} if unresolved > before else hit


func _sample(
	center: Vector2, velocity: Vector2, radius: float, elapsed: float,
	duration: float, omega: float, equalization: float, accept: Callable,
) -> Dictionary:
	var limit := velocity.length() + _top_speed_bound(elapsed, duration, omega)
	if not is_finite(limit):
		return _unresolved("vertical_top_interval")
	var time := 0.0
	for iteration in MAX_SEARCH:
		var at := elapsed + time
		var pose := parent_pose * Transform2D(start_angle + speed * minf(at, stop_time), flipper.position)
		evaluations += 1
		var gap: float = Quad.geometry(flipper, center + velocity * time, radius, pose).gap
		if gap <= GAP_TOLERANCE:
			var actual_omega := omega if at < stop_time else 0.0
			var hit := Quad.contact(flipper, center + velocity * time,
				radius + GAP_TOLERANCE, pose, actual_omega, equalization)
			if hit.is_empty():
				return _unresolved("contact_representation")
			if accept.is_valid() and not accept.call(hit):
				return _unresolved("filtered_contact")
			if hit.depth <= 0.01 and (velocity - (hit.surface_velocity as Vector2)).dot(hit.normal) >= 0.0:
				var position := center + velocity * time
				var item := flipper as TableFlipper
				# A static convex set cannot catch an outward straight path. The fixed sides
				# and bottom also give this guarantee while the top is still moving.
				if gap > 0.0 and (actual_omega == 0.0 \
					or (position.x + radius < item.fixed_left and velocity.x <= 0.0) \
					or (position.x - radius > item.fixed_right and velocity.x >= 0.0) \
					or (position.y - radius > item.fixed_bottom and velocity.y >= 0.0)):
					return {}
				unresolved_context = {"elapsed": at, "relative_time": time, "gap": gap,
					"depth": hit.depth, "normal": [hit.normal.x, hit.normal.y],
					"velocity": [velocity.x, velocity.y],
					"surface": [hit.surface_velocity.x, hit.surface_velocity.y],
					"omega": actual_omega}
				return _unresolved("nonapproaching_touch")
			hit.time = time
			hit.flipper = flipper
			return hit
		var remaining := duration - time
		if limit <= 0.0 or gap > limit * remaining:
			return {}
		# The distance to the moving convex set cannot shrink faster than this bound.
		var step := gap / limit * 0.9
		if step < 0.000000001:
			return _unresolved("time_progress")
		time = minf(duration, time + step)
	return _unresolved("iteration_limit")


func _top_speed_bound(elapsed: float, duration: float, omega: float) -> float:
	if omega == 0.0:
		return 0.0
	var inverse := parent_pose.affine_inverse()
	var cosine := inverse.y.y
	var sine := -inverse.y.x
	var amplitude := Vector2(cosine, sine).length()
	var phase := atan2(sine, cosine)
	var first := start_angle + speed * elapsed - phase
	var last := first + omega * duration
	var low := minf(first, last)
	var high := maxf(first, last)
	if floor((low - PI * 0.5) / PI) != floor((high - PI * 0.5) / PI):
		return INF
	var denominator := amplitude * minf(absf(cos(low)), absf(cos(high)))
	if denominator < 0.000001:
		return INF
	var item := flipper as TableFlipper
	var horizontal := maxf(absf(item.fixed_left - origin.x), absf(item.fixed_right - origin.x))
	var offset := absf(item._direction * item._root_radius)
	# n=P^-T*(-sin(angle), cos(angle)); top_y=(offset-n.x*dx)/n.y.
	return absf(omega) * (horizontal * absf(inverse.determinant()) + offset * amplitude) \
		/ (denominator * denominator)


func _unresolved(reason: String) -> Dictionary:
	unresolved += 1
	unresolved_reason = reason
	return {}
