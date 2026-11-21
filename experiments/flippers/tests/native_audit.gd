extends SceneTree

const Recorder = preload("res://experiments/flippers/tests/native_motion.gd")
const Counter = preload("res://experiments/flippers/tests/native_flipper.gd")
const DENSITY: int = 4096

var _main: PinballLab
var _motion: PinballMotion
var _inputs: Array
var _rows: Array[Dictionary] = []
var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json"))
	_inputs = saved.cases
	_make_main(true)
	await physics_frame
	await physics_frame
	for item: PinballFlipper in _main.flippers.items:
		_check(item.visible and item.length > 100.0, "Flipper sockets were not configured")
	if _failures > 0:
		quit(1)
		return
	for rate: float in [60.0, 30.0, 120.0]:
		for input: Dictionary in _inputs:
			_rows.append(_audit(input, rate))
			if _rows.size() % 120 == 0:
				print("Native audit: ", _rows.size(), "/", _inputs.size() * 3)
				await process_frame
	_main.free()
	_make_main(false)
	await physics_frame
	await physics_frame
	var benchmark := _benchmark()
	var integration := await _integration()
	_check(integration.get("near_enemy", []).size() == 168, "Near-enemy integration did not finish")
	_check(integration.get("population", []).size() == 4, "Population integration did not finish")
	_main.free()
	var report := {"cases": _rows, "checks": _checks, "failures": _failures,
		"godot_version": Engine.get_version_info(), "oracle_samples": DENSITY,
		"benchmark": benchmark, "integration": integration, "uncertainty_px": 0.1,
		"scope": "production PinballMotion, single flipper, first response without guard and full tick with guard 3; no global subdivision",
		"input_policy": "reuse saved start and velocity; clamp incoming to production max speed 3600; oracle recomputed at every rate",
		"separation_policy": "A uses native recovery; B uses existing upward separation for sampled contacts; no extra recovery added"}
	var file := FileAccess.open("res://experiments/flippers/evidence/native_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Native audit checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _make_main(counted: bool) -> void:
	_main = load("res://main/main.tscn").instantiate() as PinballLab
	_main.get_node("EnemySpawner").enabled = false
	if counted:
		for name: String in ["LeftFlipper", "RightFlipper"]:
			var item := _main.get_node("Playfield/Flippers/" + name) as TableFlipper
			var pivot := item.pivot_socket
			var tip := item.tip_socket
			var side := item.side
			var thickness := item.extra_thickness
			item.set_script(Counter)
			item.pivot_socket = pivot
			item.tip_socket = tip
			item.side = side
			item.extra_thickness = thickness
	root.add_child(_main)
	_main.set_physics_process(false)
	_main.ball.gravity = 0.0
	_main.ball.max_speed = 3600.0
	_main.ball.collision_mask = 8
	_main.flippers.items[0].collision_layer = 8
	_main.flippers.items[1].collision_layer = 16
	_motion = Recorder.new(_main.ball) if counted else PinballMotion.new(_main.ball)
	_motion.radius = 24.0
	_motion.gravity = 0.0
	_motion.max_speed = 3600.0
	_motion.boundary = _main.boundary
	_motion.flippers = _main.flippers
	if counted:
		(_motion as Recorder).native_response = _main.ball._resolve_contact
	else:
		_motion.native_contact = _main.ball._resolve_contact
	_motion.contact_recorded = _main.ball._record_contact
	_main.ball._motion = _motion


func _prepare(input: Dictionary) -> PinballFlipper.Swing:
	var flippers := _main.flippers
	flippers.reset_input()
	flippers.swing_angle = input.angle
	flippers.raise_speed = input.speed
	flippers.return_speed = 420.0
	if input.has("phase"):
		if input.phase > 0:
			flippers.advance(input.phase / input.speed, true, true)
	elif input.raised:
		flippers.advance(input.angle / input.speed, true, true)
	for item: PinballFlipper in flippers.items:
		item.angular_velocity = 0.0
		item.collision_layer = 8 << item.side
	var held: bool = not input.raised
	return flippers.items[0].plan_motion(held, input.angle, input.speed if held else 420.0)


func _audit(input: Dictionary, rate: float) -> Dictionary:
	var duration := 1.0 / rate
	var start := _unvec(input.start)
	var incoming := _unvec(input.velocity).limit_length(3600.0)
	var item := _main.flippers.items[0] as TableFlipper
	var swing := _prepare(input)
	var pose := item.global_transform
	_check(_gap(start, input.radius, item.world_polygon_at(pose)) > 0.1, "Input starts overlapping")
	var oracle := _oracle(item, swing, pose, start, incoming, input.radius, duration)
	_check(oracle.density_delta_ms < 0.01, "Reference unstable across densities")
	_main.flippers.pass_until_descending = false
	_main.flippers.advance(duration, not input.raised, not input.raised)
	_reset_body(input, start, incoming)
	var recorder := _motion as Recorder
	recorder.begin(duration)
	if not oracle.hit.is_empty():
		recorder.apply_swept_contact(oracle.hit)
	var reference := _first(recorder, start, incoming, duration)
	var results := {}
	for mode: String in ["native", "sampled"]:
		results[mode] = _measure(input, duration, mode == "sampled", false)
		results[mode]["frame_guard3"] = _measure(input, duration, mode == "sampled", true)
		var output: Dictionary = results[mode]
		output["end_error_px"] = _unvec(output.end).distance_to(_unvec(reference.end))
		output["velocity_error_px_s"] = _unvec(output.velocity).distance_to(_unvec(reference.velocity))
		output["angle_error_deg"] = absf(rad_to_deg(_unvec(output.velocity).angle_to(_unvec(reference.velocity)))) \
			if output.speed > 1 and reference.speed > 1 else 0.0
		output["speed_error_px_s"] = absf(output.speed - reference.speed)
		if output.found and reference.found:
			output["time_error_ms"] = absf(output.time_ms - reference.time_ms)
			output["point_error_px"] = _unvec(output.point).distance_to(_unvec(reference.point))
	if rate == 60.0 and input.id == 799:
		_check(results.native.shot and not results.sampled.found, "Known native false shot was not reproduced")
	if rate == 60.0 and input.id == 830:
		_check(results.native.found and results.sampled.found, "Stationary native collision is not active")
	if rate == 60.0 and incoming.distance_to(_unvec(input.velocity)) < 0.01:
		_check(reference.found == input.reference.found and reference.shot == input.reference.shot,
			"Reference classification differs from saved audit")
	return {"id": input.id, "suite": input.suite, "rate": rate,
		"radius": input.radius, "angle": input.angle, "raise_speed": input.speed,
		"raised": input.raised, "phase": input.get("phase", -1), "ratio": input.ratio,
		"motion": input.motion, "start": input.start, "original_velocity": input.velocity,
		"velocity": _vec(incoming), "clamped": incoming.distance_to(_unvec(input.velocity)) > 0.01,
		"min_gap_px": oracle.min_gap, "ambiguous": absf(oracle.min_gap) < 0.1,
		"density_delta_ms": oracle.density_delta_ms,
		"reference": reference, "native": results.native, "sampled": results.sampled}


func _measure(input: Dictionary, duration: float, sampled: bool, guard: bool) -> Dictionary:
	var swing := _prepare(input)
	var swings: Array[PinballFlipper.Swing] = []
	if sampled and swing != null:
		swings.append(swing)
	_main.flippers.pass_until_descending = guard
	_main.flippers.advance(duration, not input.raised, not input.raised)
	var start := _unvec(input.start)
	var incoming := _unvec(input.velocity).limit_length(3600.0)
	_reset_body(input, start, incoming)
	var item := _main.flippers.items[0] as Counter
	item.detection_checks = 0
	item.separation_checks = 0
	_main.ball.advance(duration, swings)
	var recorder := _motion as Recorder
	var first := _first(recorder, start, incoming, duration)
	first.merge({"frame_end": _vec(_main.ball.global_position), "frame_velocity": _vec(_main.ball.velocity),
		"frame_shots": recorder.events.filter(func(event: Dictionary) -> bool: return event.shot).size(),
		"contacts": recorder.events.size(), "native_queries": recorder.native_queries,
		"detection_checks": item.detection_checks, "separation_checks": item.separation_checks,
		"discarded_ms": recorder.discarded_seconds * 1000.0,
		"frame_error_from_free_px": _main.ball.global_position.distance_to(start + incoming * duration),
		"disabled": _main.flippers.is_target_disabled(_main.ball.get_instance_id())})
	if recorder.discarded_seconds > 0.0:
		first["cap_trace"] = recorder.events.duplicate(true)
	_check(_main.ball.global_position.is_finite() and _main.ball.velocity.is_finite(), "Non-finite outcome")
	_check(_main.ball.get_collision_exceptions().is_empty(), "Collision exceptions leaked")
	return first


func _reset_body(input: Dictionary, start: Vector2, incoming: Vector2) -> void:
	_main.ball.radius = input.radius
	_main.ball.reset_at(start, incoming)
	_motion.radius = input.radius


func _first(recorder: Recorder, start: Vector2, incoming: Vector2, duration: float) -> Dictionary:
	if not recorder.events.is_empty():
		return recorder.events[0].duplicate(true)
	return {"found": false, "shot": false, "changed": false, "correction_px": 0.0,
		"velocity": _vec(incoming), "speed": incoming.length(), "end": _vec(start + incoming * duration)}


func _oracle(
	item: TableFlipper, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, incoming: Vector2, radius: float, duration: float,
) -> Dictionary:
	var first := -1
	var coarse := -1
	var minimum := INF
	for index in DENSITY + 1:
		var time := duration * index / DENSITY
		var gap := _gap(start + incoming * time, radius, item.world_polygon_at(_pose(item, swing, pose, time)))
		minimum = minf(minimum, gap)
		if first < 0 and gap <= 0.0:
			first = index
		if coarse < 0 and index % 2 == 0 and gap <= 0.0:
			coarse = index
	var hit := {}
	var difference := 0.0
	if first >= 0:
		var time := _refine(item, swing, pose, start, incoming, radius, duration, first, 1)
		var other := _refine(item, swing, pose, start, incoming, radius, duration, coarse, 2) if coarse >= 0 else duration
		difference = absf(time - other) * 1000.0
		hit = item._contact_at(start + incoming * time, radius + 0.0005,
			_pose(item, swing, pose, time), swing.speed if swing != null and time < swing.stop_time else 0.0,
			_main.flippers.power_equalization)
		_check(not hit.is_empty(), "Reference contact could not be represented")
		hit["time"] = time
		hit["flipper"] = item
	return {"hit": hit, "min_gap": minimum, "density_delta_ms": difference}


func _refine(
	item: TableFlipper, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, incoming: Vector2, radius: float, duration: float, index: int, stride: int,
) -> float:
	var low := duration * maxi(0, index - stride) / DENSITY
	var high := duration * index / DENSITY
	for iteration in 22:
		var middle := (low + high) * 0.5
		if _gap(start + incoming * middle, radius, item.world_polygon_at(_pose(item, swing, pose, middle))) <= 0:
			high = middle
		else:
			low = middle
	return high


func _pose(item: TableFlipper, swing: PinballFlipper.Swing, pose: Transform2D, time: float) -> Transform2D:
	if swing == null:
		return pose
	return swing.parent_pose * Transform2D(
		swing.start_angle + swing.speed * minf(time, swing.stop_time), item.position)


func _gap(center: Vector2, radius: float, polygon: PackedVector2Array) -> float:
	# Convex half-plane test avoids near-horizontal ray/vertex ambiguity in the oracle.
	var inside := true
	var distance := INF
	for index in 4:
		var a := polygon[index]
		var b := polygon[(index + 1) % 4]
		if (b - a).cross(center - a) < 0.0:
			inside = false
		distance = minf(distance, center.distance_squared_to(Geometry2D.get_closest_point_to_segment(center, a, b)))
	return (0.0 if inside else sqrt(distance)) - radius


func _benchmark() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for run in 8:
		for sampled: bool in ([false, true] if run % 2 == 0 else [true, false]):
			var total := 0
			for input: Dictionary in _inputs:
				var swing := _prepare(input)
				var swings: Array[PinballFlipper.Swing] = []
				if sampled and swing != null:
					swings.append(swing)
				_main.flippers.pass_until_descending = true
				_main.flippers.advance(1.0 / 60.0, not input.raised, not input.raised)
				_reset_body(input, _unvec(input.start), _unvec(input.velocity).limit_length(3600.0))
				var began := Time.get_ticks_usec()
				_main.ball.advance(1.0 / 60.0, swings)
				total += Time.get_ticks_usec() - began
			if run > 0:
				results.append({"run": run, "sampled": sampled, "inputs": _inputs.size(), "total_us": total})
	return results


func _integration() -> Dictionary:
	var population: Array[Dictionary] = []
	for sampled: bool in _integration_modes():
		_select_integration_mode(sampled)
		for count: int in [1, 20]:
			_reset_integration()
			var balls: Array[PinballBall] = [_main.ball]
			for index in range(1, count):
				var ball := PinballBall.new()
				var collision := CollisionShape2D.new()
				collision.name = "CollisionShape2D"
				collision.shape = CircleShape2D.new()
				ball.add_child(collision)
				_main.get_node("Playfield").add_child(ball)
				ball.boundary = _main.boundary
				ball.flippers = _main.flippers
				_attach_recorder(ball)
				balls.append(ball)
			for index in count:
				var random := RandomNumberGenerator.new()
				random.seed = 11000 + index
				var ball := balls[index]
				ball.radius = 24.0
				ball.gravity = 1500.0
				ball.max_speed = 3600.0
				ball.collision_mask = 6
				var start := Vector2.ZERO
				var clear := false
				for attempt in 64:
					start = Vector2(random.randf_range(610, 1310), random.randf_range(180, 760))
					var query := PhysicsShapeQueryParameters2D.new()
					var circle := CircleShape2D.new()
					circle.radius = ball.radius + 0.1
					query.shape = circle
					query.transform = Transform2D(0.0, start)
					query.collision_mask = 6
					if ball.get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty():
						clear = true
						break
				_check(clear, "Population starts overlapping a world collider")
				ball.reset_at(start, Vector2(random.randf_range(-400, 400), random.randf_range(0, 500)))
			await physics_frame
			var result := {"sampled": sampled, "balls": count, "seconds": 6.0,
				"shots": 0, "contacts": 0, "exhausted_updates": 0, "discarded_ms": 0.0,
				"max_correction_px": 0.0, "below_enabled": 0, "below_disabled": 0, "exited": 0}
			for frame in 360:
				var left := fmod(frame / 60.0, 0.55) < 0.08
				var right := fmod(frame / 60.0 + 0.275, 0.55) < 0.08
				var swings := _main.flippers.plan_motion(left, right)
				_main.flippers.advance(1.0 / 60.0, left, right)
				swings = _integration_swings(swings, sampled)
				for ball: PinballBall in balls:
					if not ball.active:
						continue
					var before := ball.global_position
					var was_disabled := _main.flippers.is_target_disabled(ball.get_instance_id())
					ball.advance(1.0 / 60.0, swings)
					_collect_integration(result, ball._motion as Recorder)
					var path: Array[Vector2] = [before]
					for event: Dictionary in (ball._motion as Recorder).events:
						path.append(_unvec(event.position))
					path.append(ball.global_position)
					for index in range(path.size() - 1):
						if _crossed_bottom(path[index], path[index + 1], ball.radius):
							var disabled := was_disabled or _main.flippers.is_target_disabled(ball.get_instance_id())
							var key := "below_disabled" if disabled else "below_enabled"
							result[key] += 1
					if _main.boundary.to_local(ball.global_position).y > _main.boundary.bottom + 120.0:
						ball.active = false
						ball._motion.reset()
						result.exited += 1
				await physics_frame
			for ball: PinballBall in balls:
				_check(ball.global_position.is_finite(), "Invalid population outcome")
				if ball != _main.ball:
					ball.free()
			population.append(result)
	var near: Array[Dictionary] = []
	for sampled: bool in _integration_modes():
		_select_integration_mode(sampled)
		for ratio: float in [0.05, 0.15, 0.30, 0.50, 0.70, 0.90, 0.99]:
			for gap: float in [3, 12, 36, 72]:
				for offset: float in [-36, 0, 36]:
					_reset_integration()
					var item := _main.flippers.items[0] as TableFlipper
					var polygon := item.world_polygon_at(item.global_transform)
					_main.ball.reset_at(polygon[0].lerp(polygon[1], ratio) + Vector2.UP * 28.0, Vector2(0, 300))
					var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
					enemy.death_cue = null
					enemy.position = _main.ball.global_position + Vector2(offset, -(54.0 + gap))
					_main.get_node("Playfield").add_child(enemy)
					enemy.prepare(enemy.grow_duration)
					await physics_frame
					var result := {"sampled": sampled, "ratio": ratio, "gap": gap, "offset": offset,
						"shots": 0, "contacts": 0, "exhausted_updates": 0, "discarded_ms": 0.0,
						"max_correction_px": 0.0}
					for frame in 60:
						var swings := _main.flippers.plan_motion(true, true)
						_main.flippers.advance(1.0 / 60.0, true, true)
						swings = _integration_swings(swings, sampled)
						if is_instance_valid(enemy):
							enemy.prepare(1.0 / 60.0)
							enemy.advance(1.0 / 60.0)
						_main.ball.advance(1.0 / 60.0, swings)
						_collect_integration(result, _motion as Recorder)
						if (_motion as Recorder).discarded_seconds > 0 and not result.has("cap_trace"):
							result["cap_trace"] = (_motion as Recorder).events.duplicate(true)
						await physics_frame
					_check(_main.ball.global_position.is_finite(), "Invalid near-enemy outcome")
					if is_instance_valid(enemy):
						enemy.free()
					near.append(result)
		print("Native integration near-enemy: ", sampled, "; cases: ", near.size())
	return {"population": population, "near_enemy": near,
		"scope": "actual main layout with walls/bumpers, both flippers, guard 3; enemy retains independent movement; ball-ball collision disabled"}


func _select_integration_mode(_sampled: bool) -> void:
	pass


func _integration_modes() -> Array[bool]:
	return [false, true]


func _integration_swings(
	swings: Array[PinballFlipper.Swing], sampled: bool,
) -> Array[PinballFlipper.Swing]:
	if not sampled:
		swings.clear()
	return swings


func _reset_integration() -> void:
	_main.flippers.reset_input()
	_main.flippers.swing_angle = 18.0
	_main.flippers.raise_speed = 600.0
	_main.flippers.return_speed = 420.0
	_main.flippers.pass_until_descending = true
	for item: PinballFlipper in _main.flippers.items:
		item.collision_layer = 2
	_main.ball.collision_mask = 6
	_main.ball.gravity = 1500.0
	_main.ball.radius = 24.0
	_main.ball.hit_sound = null
	_attach_recorder(_main.ball)
	_motion = _main.ball._motion


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := Recorder.new(ball)
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	result.contacts += recorder.events.size()
	result.exhausted_updates += int(recorder.discarded_seconds > 0.0)
	result.discarded_ms += recorder.discarded_seconds * 1000.0
	for event: Dictionary in recorder.events:
		result.shots += int(event.shot)
		if event.correction_px > result.max_correction_px:
			result.max_correction_px = event.correction_px
			result["max_correction_event"] = event.duplicate(true)


func _crossed_bottom(before: Vector2, after: Vector2, radius: float) -> bool:
	for item: TableFlipper in _main.flippers.items:
		var y := item.fixed_bottom + radius
		if before.y <= y and after.y > y:
			var fraction := (y - before.y) / (after.y - before.y)
			var x := lerpf(before.x, after.x, fraction)
			if x > item.fixed_left + radius and x < item.fixed_right - radius:
				return true
	return false


static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]


static func _unvec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
