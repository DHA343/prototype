extends RefCounted


static func position_at(path: Dictionary, time: float) -> Vector2:
	if not path.has("segments"):
		return path.start + path.velocity * time
	var result: Vector2 = path.start
	for segment: Dictionary in path.segments:
		if time < segment.start_time:
			break
		result = Vector2(segment.start[0], segment.start[1]) + Vector2(
			segment.velocity[0], segment.velocity[1]) * minf(time - segment.start_time, segment.duration)
	return result


static func velocity_at(path: Dictionary, time: float) -> Vector2:
	if not path.has("segments"):
		return path.velocity
	var result := Vector2.ZERO
	for segment: Dictionary in path.segments:
		if time < segment.start_time:
			break
		result = Vector2(segment.velocity[0], segment.velocity[1])
	return result
