extends SceneTree

const Preview = preload("res://experiments/flippers/preview.gd")
const Scene = preload("res://experiments/flippers/guard_preview.tscn")
const Fixed = preload("res://experiments/flippers/fixed_flipper.gd")
const Ball = preload("res://experiments/flippers/tests/matrix_ball.gd")
const Guard = preload("res://experiments/flippers/shot_guard.gd")
const FRAME: float = 1.0 / 60.0

var checks: int = 0
var failures: int = 0
var _preview: Preview
var _query: PhysicsShapeQueryParameters2D
var _detection_results: Array[Dictionary] = []
var _response_results: Array[Dictionary] = []
var _examples: Array[Dictionary] = []
var _fixture_results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_preview = _make_preview()
	_query = PhysicsShapeQueryParameters2D.new()
	_query.margin = 0.03
	await physics_frame
	await physics_frame
	await _detection_matrix()
	await _response_matrix()
	await _corridor_fixture()
	var return_fixture := await _wall_flipper_fixture()
	var report := {"checks": checks, "failures": failures,
		"detection": _detection_results, "response": _response_results, "examples": _examples,
		"corridor": _fixture_results,
		"wall_then_flipper": return_fixture,
		"frame_seconds": FRAME, "oracle_samples": 4096, "uncertainty_band_px": 0.1,
		"correction_metric": "manual upward separation only; native recovery is not included",
		"common": ["main socket layout", "fixed X and bottom quad", "circle ball", "no ball-ball collision"],
		"guard_in_detection": false,
		"response_modes": ["one_response_end_move", "respond_at_end_too", "legacy_contact_iteration"]}
	var file := FileAccess.open("res://experiments/flippers/evidence/method_matrix.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Method matrix checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _make_preview(ball_script: GDScript = Ball) -> Preview:
	var world := SubViewport.new()
	world.size = Vector2i(1920, 1080)
	world.world_2d = World2D.new()
	root.add_child(world)
	var preview := Scene.instantiate() as Preview
	var ball := preview.get_node("Playfield/Ball") as PinballBall
	ball.set_script(ball_script)
	ball.radius = 24
	ball.gravity = 1500
	ball.max_speed = 3600
	world.add_child(preview)
	preview.set_physics_process(false)
	preview.auto_respawn = false
	return preview


func _reset_pose(raised: bool, thickness: float, swing_angle: float, speed: float) -> void:
	_preview.flippers.swing_angle = swing_angle
	_preview.flippers.raise_speed = speed
	_preview.flippers.return_speed = 420
	_preview.flippers.reset_input()
	for item: PinballFlipper in _preview.flippers.items:
		var fixed := item as Fixed
		fixed.extra_thickness = thickness
		fixed.collision_layer = 8 << item.side
	if raised:
		_preview.flippers.advance(swing_angle / speed, true, true)
		for item: PinballFlipper in _preview.flippers.items:
			item.angular_velocity = 0


func _detection_matrix() -> void:
	# Reference trajectories are fixed inputs. No bounce, correction or guard
	# is used here, so each detector sees exactly the same movement interval.
	for thickness: float in [0.0, 48.0]:
		var totals: Array[Dictionary] = []
		for split: bool in [false, true]:
			for detector in 4:
				totals.append({"split": split, "detector": detector, "extra_thickness": thickness,
					"trials": 0, "required": 0, "missed": 0, "false_hits": 0,
					"ambiguous": 0, "cpu_us": 0, "native_queries": 0,
					"sampled_sweeps": 0, "velocity_gates": 0})
		for input: Dictionary in _detection_inputs():
			var radius: float = input.radius
			_reset_pose(input.raised, thickness, input.angle, input.speed)
			var fixed := _preview.flippers.items[0] as Fixed
			var polygon := fixed.world_polygon_at(fixed.global_transform)
			var point := polygon[0].lerp(polygon[1], input.ratio)
			var start := point + Vector2.UP * (radius + 12)
			var velocity := Vector2(0, 3600)
			match input.motion:
				"rise_slow": velocity = Vector2(0, -600)
				"rise_fast": velocity = Vector2(0, -3600)
				"side_fast":
					start = point + Vector2(-42, -(radius + 12))
					velocity = Vector2(3600, 600)
				"tip_cross":
					start = point + Vector2(-12, -(radius + 8))
					velocity = Vector2(3600, 600)
			var swing := fixed.plan_motion(not input.raised, input.angle,
				420 if input.raised else input.speed)
			var pose := fixed.global_transform
			_check(_polygon_distance_squared(start, fixed.world_polygon_at(pose))
				> (radius + 0.1) * (radius + 0.1), "Detection input starts overlapping")
			var reference := _reference(fixed, swing, pose, start, velocity, radius)
			for total: Dictionary in totals:
				_reset_pose(input.raised, thickness, input.angle, input.speed)
				var began := Time.get_ticks_usec()
				var found := _detect_interval(total, not input.raised, start, velocity, radius)
				total.cpu_us += Time.get_ticks_usec() - began
				total.trials += 1
				if reference.ambiguous:
					total.ambiguous += 1
				elif reference.required:
					total.required += 1
					if not found:
						total.missed += 1
				elif found:
					total.false_hits += 1
				if _examples.size() < 48 and not reference.ambiguous and found != reference.required:
					var example := input.duplicate()
					example.merge({"thickness": thickness, "split": total.split,
						"detector": total.detector, "required": reference.required, "found": found})
					_examples.append(example)
			_check(not reference.unstable, "Reference classification changed with sample density")
			await physics_frame
		_detection_results.append_array(totals)
		for total: Dictionary in totals:
			print("Detector: ", JSON.stringify(total))


func _detection_inputs() -> Array[Dictionary]:
	var inputs: Array[Dictionary] = []
	for radius: float in [6, 24, 36]:
		for speed: float in [300, 600, 1200]:
			for raised: bool in [false, true]:
				for ratio: float in [0.2, 0.65, 0.95]:
					for angle: float in [18, 45]:
						for motion: String in ["drop", "rise_slow", "rise_fast", "side_fast", "tip_cross"]:
							inputs.append({"radius": radius, "speed": speed, "raised": raised,
								"ratio": ratio, "angle": angle, "motion": motion})
	return inputs


func _detect_interval(total: Dictionary, held: bool, start: Vector2, velocity: Vector2, radius: float) -> bool:
	var elapsed := 0.0
	var found := false
	var circle := CircleShape2D.new()
	circle.radius = radius
	_query.shape = circle
	_query.collision_mask = 8
	var space := _preview.get_world_2d().direct_space_state
	while elapsed < FRAME - 0.000001:
		var step := FRAME - elapsed
		if total.split:
			step = minf(minf(step, Preview.STEP), _preview.flippers.motion_step_limit(radius, held, held))
		var swing := _preview.flippers.items[0].plan_motion(held,
			_preview.flippers.swing_angle, _preview.flippers.raise_speed if held else 420)
		_preview.flippers.advance(step, held, held)
		var position := start + velocity * elapsed
		if total.detector == 2 and swing != null:
			total.sampled_sweeps += 1
			found = not swing.sweep(position, velocity, radius, 0, step, 0.5).is_empty() or found
		else:
			_query.transform = Transform2D(0, position + velocity * step if total.detector == 0 else position)
			_query.motion = Vector2.ZERO
			total.native_queries += 1
			var overlap := not space.intersect_shape(_query, 1).is_empty()
			var candidate := overlap
			var candidate_time := 0.0
			if total.detector != 0 and not overlap:
				_query.motion = velocity * step
				total.native_queries += 1
				var fraction := space.cast_motion(_query)
				candidate = fraction[0] < 1
				candidate_time = fraction[1] * step
			if candidate and total.detector == 3:
				total.velocity_gates += 1
				var fixed := _preview.flippers.items[0] as Fixed
				var contact := fixed._contact_at(position + velocity * candidate_time,
					radius + 0.05, fixed.global_transform, fixed.angular_velocity, 0.5)
				candidate = not contact.is_empty() \
					and (velocity - contact.surface_velocity).dot(contact.normal) < -0.01
			found = found or candidate
		elapsed += step
	return found


func _reference(
	fixed: Fixed, swing: PinballFlipper.Swing, pose: Transform2D,
	start: Vector2, velocity: Vector2, radius: float,
) -> Dictionary:
	var inner := false
	var outer := false
	var coarse_inner := false
	var coarse_outer := false
	for index in 4097:
		var time := FRAME * index / 4096.0
		var at := pose
		if swing != null:
			at = swing.parent_pose * Transform2D(swing.start_angle
				+ swing.speed * minf(time, swing.stop_time), fixed.position)
		var polygon := fixed.world_polygon_at(at)
		var center := start + velocity * time
		var distance := _polygon_distance_squared(center, polygon)
		var a := distance <= (radius - 0.1) * (radius - 0.1)
		var b := distance <= (radius + 0.1) * (radius + 0.1)
		inner = inner or a
		outer = outer or b
		if index % 2 == 0:
			coarse_inner = coarse_inner or a
			coarse_outer = coarse_outer or b
	return {"required": inner, "ambiguous": inner != outer,
		"unstable": inner != coarse_inner or outer != coarse_outer}


static func _polygon_distance_squared(center: Vector2, polygon: PackedVector2Array) -> float:
	var inside := true
	var distance := INF
	for index in 4:
		var a := polygon[index]
		var b := polygon[(index + 1) % 4]
		if (b - a).cross(center - a) < 0:
			inside = false
		distance = minf(distance, center.distance_squared_to(
			Geometry2D.get_closest_point_to_segment(center, a, b)))
	return 0.0 if inside else distance


func _response_matrix() -> void:
	for thickness: float in [0.0, 48.0]:
		for split: bool in [false, true]:
			for sweep: bool in [false, true]:
				for response_mode in 3:
					for guard_enabled: bool in [false, true]:
						await _response_case(thickness, split, sweep, response_mode, guard_enabled)


func _response_case(thickness: float, split: bool, sweep: bool, response_mode: int, guard_enabled: bool) -> void:
	_preview.set_ball_count(20)
	(_preview.flippers as Guard).reset_stats()
	_reset_pose(false, thickness, 18, 600)
	for item: PinballFlipper in _preview.flippers.items:
		item.collision_layer = 2
	for index in 20:
		var ball := _preview.balls[index] as Ball
		ball.iterative = response_mode == 2
		ball.final_response = response_mode == 1
		ball.rotation_sweep = sweep
		ball.guard_enabled = guard_enabled
		ball.collision_mask = 2
		ball.shots = 0
		ball.updates = 0
		ball.contacts = 0
		ball.end_corrections = 0
		ball.max_end_correction = 0
		ball.deferred_contacts = 0
		ball.cap_steps = 0
		ball.extra_end_contacts = 0
		ball.touched.clear()
		var random := RandomNumberGenerator.new()
		random.seed = 11000 + index
		ball.reset_at(Vector2(random.randf_range(610, 1310), random.randf_range(180, 760)),
			Vector2(random.randf_range(-400, 400), random.randf_range(0, 500)))
	await physics_frame
	var below: Dictionary[int, bool] = {}
	var outside: Dictionary[int, bool] = {}
	var cpu_us := 0
	var max_excess_move := 0.0
	for frame in 360:
		var left := fmod(frame / 60.0, 0.55) < 0.08
		var right := fmod(frame / 60.0 + 0.275, 0.55) < 0.08
		var remaining := FRAME
		var began := Time.get_ticks_usec()
		while remaining > 0.000001:
			var step := remaining
			if split:
				step = minf(minf(step, Preview.STEP), _preview.flippers.motion_step_limit(24, left, right))
			var swings := _preview.flippers.plan_motion(left, right)
			_preview.flippers.advance(step, left, right)
			for target: Ball in _preview.balls:
				if not target.active:
					continue
				var before := target.global_position
				target.advance(step, swings)
				max_excess_move = maxf(max_excess_move,
					target.global_position.distance_to(before) - target.max_speed * step)
				for item: PinballFlipper in _preview.flippers.items:
					var fixed := item as Fixed
					var floor_y := fixed.fixed_bottom + target.radius
					if before.y <= floor_y and target.global_position.y > floor_y:
						var fraction := (floor_y - before.y) / (target.global_position.y - before.y)
						var x := lerpf(before.x, target.global_position.x, fraction)
						if x > fixed.fixed_left + target.radius and x < fixed.fixed_right - target.radius:
							below[target.get_instance_id()] = true
				if target.global_position.x < 455 or target.global_position.x > 1465:
					outside[target.get_instance_id()] = true
				if _preview.boundary.to_local(target.global_position).y > _preview.boundary.bottom + 120:
					target.active = false
					(_preview.flippers as Guard).forget_ball(target)
			remaining -= step
		cpu_us += Time.get_ticks_usec() - began
		await physics_frame
	var shots := 0
	var contacts := 0
	var inactive := 0
	var max_correction := 0.0
	var end_corrections := 0
	var deferred := 0
	var caps := 0
	var extra_end := 0
	var updates := 0
	for ball: Ball in _preview.balls:
		shots += ball.shots
		contacts += ball.contacts
		inactive += int(not ball.active)
		max_correction = maxf(max_correction, maxf(ball.max_separation, ball.max_end_correction))
		end_corrections += ball.end_corrections
		deferred += ball.deferred_contacts
		caps += ball.cap_steps
		extra_end += ball.extra_end_contacts
		updates += ball.updates
		_check(is_finite(ball.global_position.y), "Invalid response position")
	var result := {"thickness": thickness, "split": split, "rotation_sweep": sweep,
		"iterative": response_mode == 2, "response_mode": response_mode,
		"guard": guard_enabled, "balls": 20, "seconds": 6,
		"shots": shots, "contacts": contacts, "inactive": inactive, "below_flipper": below.size(),
		"outside_wall": outside.size(), "max_correction": max_correction,
		"end_corrections": end_corrections, "deferred_contacts": deferred,
		"contact_cap_steps": caps, "extra_end_contacts": extra_end,
		"body_updates": updates, "max_excess_move_px": max_excess_move,
		"mean_cpu_ms": cpu_us / 360000.0}
	_response_results.append(result)
	print("Response: ", JSON.stringify(result))


func _corridor_fixture() -> void:
	_preview.set_ball_count(1)
	var walls: Array[StaticBody2D] = []
	for index in 2:
		var body := StaticBody2D.new()
		body.name = "BlockLeft" if index == 0 else "BlockRight"
		body.position = Vector2(900 if index == 0 else 996, 600)
		body.collision_layer = 2
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(6, 200)
		collision.shape = rectangle
		body.add_child(collision)
		_preview.get_node("Playfield").add_child(body)
		walls.append(body)
	await physics_frame
	_preview.boundary.wall_restitution = 1.0
	for split: bool in [false, true]:
		for mode in 3:
			_reset_pose(false, 48, 18, 600)
			for item: PinballFlipper in _preview.flippers.items:
				item.collision_layer = 2
			var ball := _preview.ball as Ball
			ball.iterative = mode == 2
			ball.final_response = mode == 1
			ball.guard_enabled = false
			ball.rotation_sweep = false
			ball.gravity = 0
			ball.contacts = 0
			ball.deferred_contacts = 0
			ball.extra_end_contacts = 0
			ball.touched.clear()
			ball.reset_at(Vector2(964, 600), Vector2(3600, 0))
			var remaining := FRAME
			while remaining > 0.000001:
				var step := minf(Preview.STEP, remaining) if split else remaining
				ball.advance(step)
				remaining -= step
			var result := {"split": split, "mode": mode,
				"position_x": ball.global_position.x, "velocity_x": ball.velocity.x,
				"contacts": ball.contacts, "deferred": ball.deferred_contacts,
				"touched": ball.touched.duplicate()}
			_fixture_results.append(result)
			_check(ball.global_position.x >= 926.8 and ball.global_position.x <= 969.2,
				"Corridor wall was crossed")
			print("Corridor: ", JSON.stringify(result))
	for wall: StaticBody2D in walls:
		wall.free()


func _wall_flipper_fixture() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for split: bool in [false, true]:
		for mode in 3:
			_reset_pose(false, 48, 18, 600)
			for item: PinballFlipper in _preview.flippers.items:
				item.collision_layer = 2
			_preview.flippers.advance(12.0 / 600.0, true, false)
			var fixed := _preview.flippers.items[0] as Fixed
			var polygon := fixed.world_polygon_at(fixed.global_transform)
			var top := polygon[0].lerp(polygon[1], 0.5)
			var wall := StaticBody2D.new()
			wall.name = "ReturnWall"
			wall.position = top + Vector2.UP * 73
			wall.collision_layer = 2
			var shape := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(160, 6)
			shape.shape = rectangle
			wall.add_child(shape)
			_preview.get_node("Playfield").add_child(wall)
			await physics_frame
			var ball := _preview.ball as Ball
			ball.iterative = mode == 2
			ball.final_response = mode == 1
			ball.rotation_sweep = true
			ball.guard_enabled = false
			ball.gravity = 0
			ball.shots = 0
			ball.touched.clear()
			ball.reset_at(top + Vector2.UP * 41, Vector2(0, -3600))
			var remaining := FRAME
			while remaining > 0.000001:
				var step := remaining
				if split:
					step = minf(minf(step, Preview.STEP), _preview.flippers.motion_step_limit(24, true, false))
				var swings := _preview.flippers.plan_motion(true, false)
				_preview.flippers.advance(step, true, false)
				ball.advance(step, swings)
				remaining -= step
			var result := {"split": split, "mode": mode, "shots": ball.shots,
				"touched": ball.touched.duplicate(), "position": ball.global_position,
				"velocity": ball.velocity}
			results.append(result)
			print("Wall-flipper: ", JSON.stringify(result))
			_check(ball.get_collision_exceptions().is_empty(), "Final-response exceptions leaked")
			wall.free()
	return results


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
