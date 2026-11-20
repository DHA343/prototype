extends "res://experiments/flippers/tests/method_matrix_test.gd"

var _rows: Array[Dictionary] = []


func _run() -> void:
	_preview = _make_preview()
	_query = PhysicsShapeQueryParameters2D.new()
	_query.margin = PinballBall.CONTACT_MARGIN
	await physics_frame
	await physics_frame
	var inputs := _detection_inputs()
	for input: Dictionary in inputs:
		input["suite"] = "previous_540"
	inputs.append_array(_main_inputs())
	for index in inputs.size():
		_rows.append(_audit(inputs[index], index))
		if index % 30 == 0:
			print("Contact audit: ", index, "/", inputs.size())
			await physics_frame
	var fixtures := await _chord_fixtures()
	var file := FileAccess.open("res://experiments/flippers/evidence/contact_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"cases": _rows, "chord": fixtures,
		"checks": checks, "failures": failures, "dt": FRAME,
		"oracle_samples": 4096, "thickness": 48,
		"scope": "isolated first response; fixed input paths, no gravity, no guard, no other contacts"}, "\t"))
	print("Contact audit checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _main_inputs() -> Array[Dictionary]:
	var inputs: Array[Dictionary] = []
	for phase: float in [0, 3, 6, 9, 12, 15, 18]:
		for returning: bool in [false, true]:
			for ratio: float in [0.2, 0.65, 0.95]:
				for motion: String in ["drop_slow", "drop_medium", "drop", "rise_slow",
					"rise_fast", "side_right_main", "side_left_main", "still"]:
					inputs.append({"suite": "main_336", "radius": 24.0, "speed": 600.0,
						"raised": returning, "ratio": ratio, "angle": 18.0,
						"phase": phase, "motion": motion})
	return inputs


func _prepare(input: Dictionary) -> void:
	_reset_pose(input.raised if not input.has("phase") else false, 48, input.angle, input.speed)
	if input.has("phase") and input.phase > 0:
		_preview.flippers.advance(input.phase / input.speed, true, true)
		for item: PinballFlipper in _preview.flippers.items:
			item.angular_velocity = 0


func _audit(input: Dictionary, id: int) -> Dictionary:
	_prepare(input)
	var fixed := _preview.flippers.items[0] as Fixed
	var pose := fixed.global_transform
	var points := fixed.world_polygon_at(pose)
	var point := points[0].lerp(points[1], input.ratio)
	var radius: float = input.radius
	var start := point + Vector2.UP * (radius + 12)
	var velocity := Vector2(0, 3600)
	match input.motion:
		"drop_slow": velocity = Vector2(0, 300)
		"drop_medium": velocity = Vector2(0, 1200)
		"rise_slow": velocity = Vector2(0, -600)
		"rise_fast": velocity = Vector2(0, -3600)
		"side_fast":
			start = point + Vector2(-42, -(radius + 12))
			velocity = Vector2(3600, 600)
		"tip_cross":
			start = point + Vector2(-12, -(radius + 8))
			velocity = Vector2(3600, 600)
		"side_right_main": velocity = Vector2(3000, 600)
		"side_left_main": velocity = Vector2(-3000, 600)
		"still": velocity = Vector2.ZERO
	var held: bool = not input.raised
	var swing := fixed.plan_motion(held, input.angle, 420 if input.raised else input.speed)
	var reference := _oracle(fixed, swing, pose, start, velocity, radius)
	var sampled := {}
	var began := Time.get_ticks_usec()
	if swing != null:
		sampled = swing.sweep(start, velocity, radius, 0, FRAME, _preview.flippers.power_equalization)
	var sample_us := Time.get_ticks_usec() - began
	began = Time.get_ticks_usec()
	var refined := _refine_sample(fixed, swing, pose, start, velocity, radius, sampled)
	var refine_us := Time.get_ticks_usec() - began
	var refined_short := _refine_sample(fixed, swing, pose, start, velocity, radius, sampled, 4)
	_preview.flippers.advance(FRAME, held, held)
	var ball := _preview.ball as Ball
	ball.radius = radius
	ball.gravity = 0
	ball.collision_mask = 8
	ball.guard_enabled = false
	ball.reset_at(start, velocity)
	# Keep the original 540 input paths, including diagonal speed 3,649.66 px/s.
	ball.velocity = velocity
	var cast_found := _cast_found(start, velocity, radius)
	var native := ball.move_and_collide(velocity * FRAME, true, PinballBall.CONTACT_MARGIN, true)
	var frozen := _native_outcome(ball, native, start, velocity)
	var timed := _timed_native_outcome(fixed, swing, native, frozen, start, velocity)
	var exact := _swept_outcome(ball, reference.hit, start, velocity)
	# Stationary flippers use the same native cast as production, never the oracle.
	var sample_out := _swept_outcome(ball, sampled, start, velocity) if swing != null else frozen.duplicate(true)
	var refined_out := _swept_outcome(ball, refined, start, velocity) if swing != null else frozen.duplicate(true)
	var short_out := _swept_outcome(ball, refined_short, start, velocity) if swing != null else frozen.duplicate(true)
	var record := input.duplicate()
	record.merge({"id": id, "start": _vec(start), "velocity": _vec(velocity),
		"reference": exact, "frozen": frozen, "frozen_timed": timed,
		"sampled": sample_out, "refined": refined_out, "refined4": short_out,
		"cast_found": cast_found, "min_gap_px": reference.min_gap,
		"sample_detection_us": sample_us, "refine_added_us": refine_us,
		"ambiguous": absf(reference.min_gap) < 0.1,
		"oracle_time_density_delta_ms": reference.density_delta_ms})
	if frozen.found:
		var at := _pose_at(swing, pose, fixed, frozen.time_ms / 1000.0)
		record["actual_gap_at_frozen_hit_px"] = _gap(start + velocity * frozen.time_ms / 1000.0,
			radius, fixed.world_polygon_at(at))
	for name: String in ["frozen", "frozen_timed", "sampled", "refined", "refined4"]:
		var result: Dictionary = record[name]
		result["velocity_delta_px_s"] = _unvec(result.velocity).distance_to(_unvec(exact.velocity))
		result["end_delta_px"] = _unvec(result.end).distance_to(_unvec(exact.end))
		result["speed_delta_px_s"] = result.speed - exact.speed
		result["angle_delta_deg"] = absf(rad_to_deg(_unvec(result.velocity).angle_to(_unvec(exact.velocity)))) \
			if result.speed > 1 and exact.speed > 1 else 0.0
		if result.found and exact.found:
			result["time_delta_ms"] = result.time_ms - exact.time_ms
			result["contact_point_delta_px"] = _unvec(result.point).distance_to(_unvec(exact.point))
			result["ratio_delta_percent"] = (result.ratio - exact.ratio) * 100
	_check(_gap(start, radius, points) > 0.1, "Audit input starts overlapping")
	_check(reference.density_delta_ms < 0.01, "Reference first hit unstable across densities")
	_check(is_finite(frozen.speed) and is_finite(sample_out.speed), "Non-finite response")
	record["frozen_frame"] = _frame_outcome(input, start, velocity, false)
	record["sampled_frame"] = _frame_outcome(input, start, velocity, true)
	return record


func _cast_found(start: Vector2, velocity: Vector2, radius: float) -> bool:
	var shape := CircleShape2D.new()
	shape.radius = radius
	_query.shape = shape
	_query.collision_mask = 8
	_query.transform = Transform2D(0, start)
	_query.motion = Vector2.ZERO
	var space := _preview.get_world_2d().direct_space_state
	if not space.intersect_shape(_query, 1).is_empty():
		return true
	_query.motion = velocity * FRAME
	return space.cast_motion(_query)[0] < 1.0


func _refine_sample(
	fixed: Fixed, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, velocity: Vector2, radius: float, hit: Dictionary, iterations: int = 12,
) -> Dictionary:
	if hit.is_empty() or swing == null or hit.time <= 0:
		return hit
	var turning := clampf(swing.stop_time, 0, FRAME)
	var segment_start := 0.0 if hit.time <= turning + 0.0000001 else turning
	var duration := turning if segment_start == 0 else FRAME - turning
	var omega := swing.speed if segment_start == 0 else 0.0
	if duration <= 0:
		return hit
	var count := maxi(1, ceili((velocity.length() + absf(omega) * swing.reach) * duration / 4.0))
	var index := roundi((hit.time - segment_start) * count / duration)
	var low := segment_start + duration * maxi(0, index - 1) / count
	var high: float = hit.time
	if _gap(start + velocity * low, radius, fixed.world_polygon_at(_pose_at(swing, pose, fixed, low))) <= 0:
		return hit
	for iteration in iterations:
		var middle := (low + high) * 0.5
		if _gap(start + velocity * middle, radius,
			fixed.world_polygon_at(_pose_at(swing, pose, fixed, middle))) <= 0:
			high = middle
		else:
			low = middle
	var result := fixed._contact_at(start + velocity * high, radius + 0.0005,
		_pose_at(swing, pose, fixed, high), _omega_at(swing, high), _preview.flippers.power_equalization)
	result["time"] = high
	result["flipper"] = fixed
	return result


func _frame_outcome(input: Dictionary, start: Vector2, incoming: Vector2, swept: bool) -> Dictionary:
	_prepare(input)
	var fixed := _preview.flippers.items[0] as Fixed
	var swing := fixed.plan_motion(not input.raised, input.angle, 420 if input.raised else input.speed)
	var swings: Array[PinballFlipper.Swing] = []
	if swing != null:
		swings.append(swing)
	_preview.flippers.advance(FRAME, not input.raised, not input.raised)
	var ball := _preview.ball as Ball
	ball.rotation_sweep = swept
	ball.iterative = true
	ball.guard_enabled = true
	ball.gravity = 0
	ball.radius = input.radius
	ball.collision_mask = 8
	ball.reset_at(start, incoming)
	ball.shots = 0
	ball.contacts = 0
	ball.cap_steps = 0
	ball.advance(FRAME, swings)
	var free_end := start + incoming.limit_length(ball.max_speed) * FRAME
	return {"position": _vec(ball.global_position), "velocity": _vec(ball.velocity),
		"speed": ball.velocity.length(), "shot": ball.shots > 0,
		"contacts": ball.contacts, "caps": ball.cap_steps,
		"deviation_from_free_end_px": ball.global_position.distance_to(free_end)}


func _oracle(
	fixed: Fixed, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, velocity: Vector2, radius: float,
) -> Dictionary:
	var first := -1
	var coarse := -1
	var minimum := INF
	for index in 4097:
		var time := FRAME * index / 4096.0
		var at := _pose_at(swing, pose, fixed, time)
		var gap := _gap(start + velocity * time, radius, fixed.world_polygon_at(at))
		minimum = minf(minimum, gap)
		if first < 0 and gap <= 0:
			first = index
		if coarse < 0 and index % 2 == 0 and gap <= 0:
			coarse = index
	var hit := {}
	var density_delta := 0.0
	if first >= 0:
		var time := _refine(fixed, swing, pose, start, velocity, radius, first, 1)
		var other := _refine(fixed, swing, pose, start, velocity, radius, coarse, 2) if coarse >= 0 else FRAME
		density_delta = absf(time - other) * 1000
		hit = fixed._contact_at(start + velocity * time, radius + 0.0005,
			_pose_at(swing, pose, fixed, time), _omega_at(swing, time), _preview.flippers.power_equalization)
		_check(not hit.is_empty(), "Oracle hit could not be represented")
		hit["time"] = time
		hit["flipper"] = fixed
	return {"hit": hit, "min_gap": minimum, "density_delta_ms": density_delta}


func _refine(
	fixed: Fixed, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, velocity: Vector2, radius: float, index: int, stride: int,
) -> float:
	var low := FRAME * maxi(0, index - stride) / 4096.0
	var high := FRAME * index / 4096.0
	for iteration in 22:
		var middle := (low + high) * 0.5
		var gap := _gap(start + velocity * middle, radius,
			fixed.world_polygon_at(_pose_at(swing, pose, fixed, middle)))
		if gap <= 0:
			high = middle
		else:
			low = middle
	return high


func _pose_at(swing: PinballFlipper.Swing, pose: Transform2D, fixed: Fixed, time: float) -> Transform2D:
	if swing == null:
		return pose
	return swing.parent_pose * Transform2D(swing.start_angle + swing.speed * minf(time, swing.stop_time), fixed.position)


func _omega_at(swing: PinballFlipper.Swing, time: float) -> float:
	return swing.speed if swing != null and time < swing.stop_time else 0.0


func _gap(center: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	return sqrt(_polygon_distance_squared(center, polygon)) - radius


func _native_outcome(ball: Ball, collision: KinematicCollision2D, start: Vector2, incoming: Vector2) -> Dictionary:
	if collision == null:
		return _empty_outcome(start, incoming)
	var fraction := 0.0
	var motion := incoming * FRAME
	if motion.length_squared() > 0.000001:
		fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0, 1)
	var time := fraction * FRAME
	var point := collision.get_position()
	var item := collision.get_collider() as Fixed
	_check(item == _preview.flippers.items[0], "Unexpected collider in frozen audit")
	ball.global_position = start + collision.get_travel()
	ball.shots = 0
	ball._resolve_contact(collision)
	ball.velocity = ball.velocity.limit_length(ball.max_speed)
	return {"found": true, "time_ms": time * 1000, "point": _vec(point),
		"ratio": item.contact_ratio(point), "normal": _vec(collision.get_normal()),
		"velocity": _vec(ball.velocity), "speed": ball.velocity.length(), "shot": ball.shots > 0,
		"changed": incoming.distance_to(ball.velocity) > 0.01,
		"correction_px": (collision.get_travel() - incoming * time).length(),
		"end": _vec(ball.global_position + ball.velocity * (FRAME - time))}


func _timed_native_outcome(
	fixed: Fixed, swing: PinballFlipper.Swing, collision: KinematicCollision2D,
	frozen: Dictionary, start: Vector2, incoming: Vector2,
) -> Dictionary:
	if collision == null:
		return frozen.duplicate(true)
	# Change only the motion state at the native estimated time. Keep the native
	# endpoint-pose geometry, normal, point and recovery, to isolate this refinement.
	var result := frozen.duplicate(true)
	var time: float = result.time_ms / 1000.0
	var omega := _omega_at(swing, time)
	var point := collision.get_position()
	var normal := collision.get_normal()
	var striking := omega * fixed._direction > 0 and fixed.to_local(point).x > 0 \
		and normal.dot(fixed.strike_normal()) > 0.5
	var surface := Vector2.ZERO
	var strike_surface := Vector2.ZERO
	if fixed._is_upper_contact(point, fixed.global_transform):
		var arm := point - fixed.global_position
		var reach := fixed.tip_position() - fixed.global_position
		surface = fixed._upper_velocity(fixed._point_velocity(arm, reach, omega, 0), fixed.global_transform)
		strike_surface = fixed._upper_velocity(fixed._point_velocity(arm, reach, omega,
			_preview.flippers.power_equalization), fixed.global_transform)
	var speed := -(incoming - surface).dot(normal)
	var outgoing := incoming
	if speed > 0:
		outgoing = PinballBall.reflected_velocity(incoming, normal, _preview.flippers.restitution,
			strike_surface if striking else surface)
		if striking:
			outgoing = _preview.flippers.direct_shot(outgoing, result.ratio, fixed.side, normal)
	outgoing = outgoing.limit_length(3600)
	result["velocity"] = _vec(outgoing)
	result["speed"] = outgoing.length()
	result["shot"] = striking and speed > 0
	result["changed"] = incoming.distance_to(outgoing) > 0.01
	result["end"] = _vec(start + collision.get_travel() + outgoing * (FRAME - time))
	return result


func _swept_outcome(ball: Ball, hit: Dictionary, start: Vector2, incoming: Vector2) -> Dictionary:
	if hit.is_empty():
		return _empty_outcome(start, incoming)
	ball.reset_at(start, incoming)
	ball.velocity = incoming
	ball.shots = 0
	ball.max_separation = 0
	ball._apply_swept_contact(hit)
	ball.velocity = ball.velocity.limit_length(ball.max_speed)
	return {"found": true, "time_ms": hit.time * 1000, "point": _vec(hit.point),
		"ratio": hit.ratio, "normal": _vec(hit.normal), "velocity": _vec(ball.velocity),
		"speed": ball.velocity.length(), "shot": ball.shots > 0,
		"changed": incoming.distance_to(ball.velocity) > 0.01,
		"correction_px": ball.max_separation,
		"end": _vec(ball.global_position + ball.velocity * (FRAME - hit.time))}


func _empty_outcome(start: Vector2, incoming: Vector2) -> Dictionary:
	return {"found": false, "velocity": _vec(incoming), "speed": incoming.length(),
		"shot": false, "changed": false, "end": _vec(start + incoming * FRAME), "correction_px": 0.0}


func _chord_fixtures() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	_preview.set_ball_count(1)
	for kind: String in ["extra_target", "missed_target"]:
		for mode: int in [1, 2]:
			_reset_pose(false, 48, 18, 600)
			for item: PinballFlipper in _preview.flippers.items:
				item.collision_layer = 0
			var wall := StaticBody2D.new()
			wall.name = "TurnWall"
			wall.position = Vector2(1000, 600)
			wall.collision_layer = 2
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(6, 30)
			shape.shape = rectangle
			wall.add_child(shape)
			_preview.get_node("Playfield").add_child(wall)
			var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
			enemy.name = "Target"
			enemy.position = Vector2(912, 582) if kind == "extra_target" else Vector2(989, 660)
			_preview.get_node("Playfield").add_child(enemy)
			enemy.prepare(enemy.grow_duration)
			var ball := _preview.ball as Ball
			ball.radius = 24
			ball.iterative = mode == 2
			ball.final_response = mode == 1
			ball.rotation_sweep = false
			ball.guard_enabled = false
			ball.gravity = 0
			ball.collision_mask = 6
			ball.damage = 50
			ball.damage_per_speed = 0
			ball.contacts = 0
			ball.touched.clear()
			_preview.boundary.wall_restitution = 1
			ball.reset_at(Vector2(964, 600), Vector2(2400, 1800))
			await physics_frame
			ball.advance(FRAME)
			var health_loss := enemy.max_health - enemy.current_health
			results.append({"kind": kind, "mode": mode, "enemy_position": _vec(enemy.position),
				"health_loss": health_loss, "touched": ball.touched.duplicate(),
				"position": _vec(ball.global_position), "velocity": _vec(ball.velocity)})
			var expected_hit := (kind == "extra_target") == (mode == 1)
			_check((health_loss > 0) == expected_hit, "Chord fixture did not separate intended targets")
			wall.free()
			enemy.free()
	return results


static func _vec(value: Vector2) -> Array:
	return [value.x, value.y]


static func _unvec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
