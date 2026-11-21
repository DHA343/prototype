extends RefCounted


static func geometry(
	item: TableFlipper, center: Vector2, radius: float, pose: Transform2D,
) -> Dictionary:
	var points := item.world_polygon_at(pose)
	var top_edge := points[1] - points[0]
	var top := points[0] + top_edge * clampf((center - points[0]).dot(top_edge) / top_edge.length_squared(), 0.0, 1.0)
	var nearest := top
	var distance := center.distance_squared_to(top)
	var edge := 0
	var candidate := Vector2(item.fixed_right, clampf(center.y, points[1].y, item.fixed_bottom))
	var other := center.distance_squared_to(candidate)
	if other < distance:
		distance = other
		nearest = candidate
		edge = 1
	candidate = Vector2(clampf(center.x, item.fixed_left, item.fixed_right), item.fixed_bottom)
	other = center.distance_squared_to(candidate)
	if other < distance:
		distance = other
		nearest = candidate
		edge = 2
	candidate = Vector2(item.fixed_left, clampf(center.y, points[0].y, item.fixed_bottom))
	other = center.distance_squared_to(candidate)
	if other < distance:
		distance = other
		nearest = candidate
		edge = 3
	var inside := center.x >= item.fixed_left and center.x <= item.fixed_right \
		and center.y <= item.fixed_bottom and top_edge.cross(center - points[0]) >= 0.0
	var gap := (0.0 if inside else sqrt(distance)) - radius
	if gap > 0.0:
		return {"gap": gap}
	var normal := (center - nearest).normalized()
	if inside or normal == Vector2.ZERO:
		var segment := points[(edge + 1) % 4] - points[edge]
		normal = Vector2(segment.y, -segment.x).normalized()
	return {"point": nearest, "normal": normal, "inside": inside, "edge": edge,
		"gap": gap,
		"depth": radius + sqrt(distance) if inside else radius - sqrt(distance),
		"on_top": edge == 0 or nearest.distance_squared_to(points[0]) < 0.000004 \
			or nearest.distance_squared_to(points[1]) < 0.000004}


static func contact(
	item: TableFlipper, center: Vector2, radius: float,
	pose: Transform2D, omega: float, equalization: float,
) -> Dictionary:
	var shape := geometry(item, center, radius, pose)
	if shape.gap > 0.0:
		return {}
	var point: Vector2 = shape.point
	var normal: Vector2 = shape.normal
	var arm := point - pose.origin
	var end := pose * item._tip.position
	var contact_x := (pose.affine_inverse() * point).x
	var ratio := clampf(contact_x / item.length, 0.0, 1.0)
	var upper := pose.basis_xform(Vector2(0.0, item._direction)).normalized()
	var on_shot_face: bool = shape.on_top and contact_x > 0.0 and normal.dot(upper) > 0.5
	var striking := omega * item._direction > 0.0 and on_shot_face
	var surface := Vector2.ZERO
	var strike_surface := Vector2.ZERO
	if shape.on_top:
		var rotating := PinballFlipper._point_velocity(arm, end - pose.origin, omega, 0.0)
		surface = Vector2(0.0, rotating.dot(upper) / upper.y)
		rotating = PinballFlipper._point_velocity(arm, end - pose.origin, omega,
			equalization if striking else 0.0)
		strike_surface = Vector2(0.0, rotating.dot(upper) / upper.y)
	return {"point": point, "normal": normal, "pose": pose, "depth": shape.depth,
		"surface_velocity": surface, "strike_surface_velocity": strike_surface,
		"ratio": ratio, "on_shot_face": on_shot_face, "is_striking": striking}
