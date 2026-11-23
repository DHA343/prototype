extends RefCounted


static func depth(actor: PhysicsBody2D, center: Vector2, radius: float) -> float:
	if actor is Enemy or actor is PinballBumper:
		return maxf(0.0, radius + actor.radius - center.distance_to(actor.global_position))
	if actor is PinballFlipper:
		return actor._contact_at(center, radius, actor.global_transform, 0.0, 0.0).get("depth", 0.0)
	var collision := actor.get_child(0) as CollisionShape2D
	var segments := collision.shape as ConcavePolygonShape2D
	var nearest := INF
	if segments != null:
		for index: int in range(0, segments.segments.size(), 2):
			nearest = minf(nearest, center.distance_to(Geometry2D.get_closest_point_to_segment(
				center, collision.to_global(segments.segments[index]),
				collision.to_global(segments.segments[index + 1]))))
	return maxf(0.0, radius - nearest)
