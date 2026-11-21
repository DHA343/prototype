extends "res://experiments/flippers/tests/native_audit.gd"

const Quad = preload("res://experiments/flippers/quad_contact.gd")
const QuadSwing = preload("res://experiments/flippers/quad_swing.gd")

var _point_count: int = 0
var _mismatches: Array[Dictionary] = []
var _maximum: Dictionary = {"point": 0.0, "normal_deg": 0.0, "depth": 0.0, "surface": 0.0}
var _d1_rows: Array[Dictionary] = []
var _reference_errors: Array[Dictionary] = []
var _boundary_count: int = 0
var _tie_count: int = 0


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	for saved: Dictionary in previous.cases:
		var input: Dictionary = _inputs[int(saved.id)]
		var swing := _prepare(input)
		var item := _main.flippers.items[0] as TableFlipper
		var start := _unvec(saved.start)
		var incoming := _unvec(saved.velocity)
		var duration: float = 1.0 / saved.rate
		if swing != null:
			var moving := minf(swing.stop_time, duration)
			_compare_samples(item, swing, start, incoming, input.radius, 0.0, moving, swing.speed)
			if moving < duration:
				_compare_samples(item, swing, start + incoming * moving, incoming,
					input.radius, moving, duration - moving, 0.0)
			var specialized := _copy_swing(swing)
			var baseline := swing.sweep(start, incoming, input.radius, 0.0, duration,
				_main.flippers.power_equalization)
			var candidate := specialized.sweep(start, incoming, input.radius, 0.0, duration,
				_main.flippers.power_equalization)
			_d1_rows.append({"id": saved.id, "rate": saved.rate,
				"ambiguous": saved.ambiguous, "baseline": _pack(baseline), "candidate": _pack(candidate)})
		if int(saved.id) % 150 == 0:
			print("Quad D1 poses: ", _point_count)
			await process_frame
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/independent_audit.json"))
	for input: Dictionary in extra.recovery:
		_set_fixed_pose(input.angle)
		var item := _main.flippers.items[int(input.side)] as TableFlipper
		_compare_point(item, _unvec(input.start), input.radius, item.global_transform, 0.0)
	for input: Dictionary in extra.detection:
		_set_fixed_pose(input.angle)
		var item := _main.flippers.items[int(input.side)] as TableFlipper
		for fraction: float in [0.0, 0.5, 1.0]:
			_compare_point(item, _unvec(input.start) + _unvec(input.velocity) * fraction / input.rate,
				input.radius, item.global_transform, 0.0)
	var file := FileAccess.open("res://experiments/flippers/evidence/quad_d1.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"poses": _point_count, "mismatches": _mismatches, "maximum": _maximum,
		"sweeps": _d1_rows, "reference_errors": _reference_errors,
		"boundary_count": _boundary_count, "tie_count": _tie_count}, "\t"))
	_main.free()
	print("Quad D1 checks: ", _checks, "; failures: ", _failures, "; mismatches: ", _mismatches.size())
	quit(0 if _failures == 0 else 1)


func _set_fixed_pose(angle: float) -> void:
	_main.flippers.reset_input()
	_main.flippers.swing_angle = 18.0
	if angle > 0.0:
		_main.flippers.advance(angle / 600.0, true, true)


func _copy_swing(source: PinballFlipper.Swing) -> QuadSwing:
	var swing := QuadSwing.new()
	for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
		swing.set(property, source.get(property))
	return swing


func _compare_samples(
	item: TableFlipper, swing: PinballFlipper.Swing, start: Vector2,
	incoming: Vector2, radius: float, elapsed: float, duration: float, omega: float,
) -> void:
	var travel := (incoming.length() + absf(omega) * swing.reach) * duration
	var count := maxi(1, ceili(travel / 4.0))
	for index in range(count + 1 if duration > 0.0 else 1):
		var time := duration * index / count
		_compare_point(item, start + incoming * time, radius,
			_pose(item, swing, item.global_transform, elapsed + time), omega)


func _compare_point(item: TableFlipper, center: Vector2, radius: float, pose: Transform2D, omega: float) -> void:
	_point_count += 1
	var position := _main.ball.global_position
	var baseline := item._contact_at(center, radius, pose, omega, _main.flippers.power_equalization)
	var candidate := Quad.contact(item, center, radius, pose, omega, _main.flippers.power_equalization)
	var reference := _reference_geometry(item, center, radius, pose)
	var boundary: bool = reference.edge_distance < 0.0015
	var tie: bool = reference.tie
	_boundary_count += int(boundary)
	_tie_count += int(tie)
	var error := {}
	if (reference.gap < -0.001 and candidate.is_empty()) or (reference.gap > 0.001 and not candidate.is_empty()):
		error = {"kind": "presence", "gap": reference.gap}
	elif not candidate.is_empty() and reference.gap <= 0.001:
		var reference_depth: float = radius + reference.edge_distance if reference.inside else -reference.gap
		var normal_error := absf(rad_to_deg((candidate.normal as Vector2).angle_to(reference.normal)))
		if absf(candidate.depth - reference_depth) > 0.001 \
			or (not tie and candidate.point.distance_to(reference.point) > 0.001) \
			or (not tie and not boundary and normal_error > 0.1):
			error = {"kind": "geometry", "normal_error": normal_error, "reference": reference}
	if not error.is_empty():
		error.merge({"center": _vec(center), "radius": radius, "boundary": boundary,
			"tie": tie, "candidate": _pack(candidate)})
		_reference_errors.append(error)
	_check(_main.ball.global_position == position, "D1 contact calculation moved the ball")
	if baseline.is_empty() != candidate.is_empty():
		_mismatches.append({"kind": "presence", "center": _vec(center), "radius": radius,
			"gap": _gap(center, radius, item.world_polygon_at(pose)),
			"baseline": _pack(baseline), "candidate": _pack(candidate)})
		return
	if baseline.is_empty():
		return
	var point: float = baseline.point.distance_to(candidate.point)
	var normal := absf(rad_to_deg((baseline.normal as Vector2).angle_to(candidate.normal)))
	var depth := absf(float(baseline.depth) - float(candidate.depth))
	var surface: float = baseline.surface_velocity.distance_to(candidate.surface_velocity)
	_maximum.point = maxf(_maximum.point, point)
	_maximum.normal_deg = maxf(_maximum.normal_deg, normal)
	_maximum.depth = maxf(_maximum.depth, depth)
	_maximum.surface = maxf(_maximum.surface, surface)
	if point > 0.001 or normal > 0.1 or depth > 0.001 or surface > 0.1 \
		or baseline.is_striking != candidate.is_striking:
		_mismatches.append({"kind": "geometry_or_state", "center": _vec(center), "radius": radius,
			"point_error": point, "normal_error": normal, "depth_error": depth, "surface_error": surface,
			"boundary": boundary, "tie": tie, "reference_inside": reference.inside,
			"edge_distance": reference.edge_distance, "pose": [_vec(pose.x), _vec(pose.y), _vec(pose.origin)],
			"baseline": _pack(baseline), "candidate": _pack(candidate)})


func _reference_geometry(item: TableFlipper, center: Vector2, radius: float, pose: Transform2D) -> Dictionary:
	var points := item.world_polygon_at(pose)
	var inside := true
	var distances: Array[float] = []
	var closest := Vector2.ZERO
	var distance := INF
	var face := Vector2.ZERO
	for index in 4:
		var a := points[index]
		var b := points[(index + 1) % 4]
		var segment := b - a
		inside = inside and segment.cross(center - a) >= 0.0
		var point := Geometry2D.get_closest_point_to_segment(center, a, b)
		var candidate := center.distance_to(point)
		distances.append(candidate)
		if candidate < distance:
			distance = candidate
			closest = point
			face = Vector2(segment.y, -segment.x).normalized()
	distances.sort()
	return {"inside": inside, "point": closest,
		"normal": face if inside else (center - closest).normalized(),
		"gap": (0.0 if inside else distance) - radius, "edge_distance": distance,
		"tie": inside and distances[1] - distances[0] < 0.001}


func _pack(hit: Dictionary) -> Dictionary:
	if hit.is_empty():
		return {"found": false}
	return {"found": true, "point": _vec(hit.point), "normal": _vec(hit.normal),
		"depth": hit.depth, "striking": hit.is_striking, "surface": _vec(hit.surface_velocity),
		"time": hit.get("time", -1.0)}
