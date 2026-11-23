extends RefCounted


static func gap(center: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	# Independent scalar convex-polygon test: do not reuse the production inside predicate.
	var positive := false
	var negative := false
	var nearest := INF
	for index: int in polygon.size():
		var a := polygon[index]
		var b := polygon[(index + 1) % polygon.size()]
		var dx: float = float(b.x) - float(a.x)
		var dy: float = float(b.y) - float(a.y)
		var rx: float = float(center.x) - float(a.x)
		var ry: float = float(center.y) - float(a.y)
		var cross := dx * ry - dy * rx
		positive = positive or cross > 0.0
		negative = negative or cross < 0.0
		var fraction := clampf((rx * dx + ry * dy) / (dx * dx + dy * dy), 0.0, 1.0)
		nearest = minf(nearest, sqrt(pow(rx - fraction * dx, 2) + pow(ry - fraction * dy, 2)))
	return nearest - radius if positive and negative else -nearest - radius


static func first_contact(
	plans: Array[PinballFlipper.Swing], start: Vector2, velocity: Vector2,
	radius: float, duration: float, equalization: float, density: int,
) -> Dictionary:
	var first := {}
	for plan: PinballFlipper.Swing in plans:
		for index: int in density + 1:
			var time := duration * float(index) / density
			var pose := _pose(plan, time)
			var polygon := (plan.flipper as TableFlipper).world_polygon_at(pose)
			if gap(start + velocity * time, radius, polygon) > 0.0: continue
			var low := duration * maxi(0, index - 1) / density
			var high := time
			for iteration: int in 22:
				var middle := (low + high) * .5
				polygon = (plan.flipper as TableFlipper).world_polygon_at(_pose(plan, middle))
				if gap(start + velocity * middle, radius, polygon) > 0.0: low = middle
				else: high = middle
			var hit := plan.flipper._contact_at(start + velocity * high, radius + .0005,
				_pose(plan, high), plan.speed if high < plan.stop_time else 0.0, equalization)
			assert(not hit.is_empty(), "Independent contact has no production contact metadata")
			hit.time = high
			hit.flipper = plan.flipper
			if first.is_empty() or high < first.time: first = hit
			break
	return first


static func _pose(plan: PinballFlipper.Swing, time: float) -> Transform2D:
	return plan.parent_pose * Transform2D(
		plan.start_angle + plan.speed * minf(time, plan.stop_time), plan.flipper.position)
