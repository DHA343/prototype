extends SceneTree

const Preview = preload("res://experiments/flippers/preview.gd")
const Guard = preload("res://experiments/flippers/shot_guard.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")
const Probe = preload("res://experiments/flippers/tests/multiball_probe.gd")
const GuardScene = preload("res://experiments/flippers/guard_preview.tscn")
const STEP: float = 1.0 / 240.0

var checks: int = 0
var failures: int = 0
var results: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if "--reflector-only" in OS.get_cmdline_user_args():
		await _case(0, 40, "reflector", 11, 20, 6.0)
		quit(0 if failures == 0 else 1)
		return
	for mode: int in [0, 1]:
		await _isolation(mode)
	for setting: Vector2 in [Vector2(0, 40), Vector2(1, 40), Vector2(1, 5)]:
		await _case(int(setting.x), setting.y, "overlap", 11, 20, 0.2)
		for seed_value in [11, 29, 73]:
			await _case(int(setting.x), setting.y, "fall", seed_value, 20, 8.0)
		await _case(int(setting.x), setting.y, "mixed", 11, 20, 8.0)
		await _case(int(setting.x), setting.y, "alternating", 11, 20, 8.0)
		await _case(int(setting.x), setting.y, "reflector", 11, 20, 6.0)
		await _case(int(setting.x), setting.y, "volley", 11, 20, 4.0)
		await _case(int(setting.x), setting.y, "fall", 11, 50, 8.0)
	await _case(1, 100, "reflector", 11, 20, 6.0)
	var report := {"checks": checks, "failures": failures, "cases": results,
		"ball_ball_collisions": false, "hole_width_px": 84,
		"step_seconds": STEP, "auto_respawn": false}
	var file := FileAccess.open("res://experiments/flippers/evidence/multiball_guard.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Multiball checks: ", checks, "; failures: ", failures)
	quit(0 if failures == 0 else 1)


func _make_preview(mode: int, duration: float, count: int) -> Preview:
	var world := SubViewport.new()
	world.size = Vector2i(1920, 1080)
	world.world_2d = World2D.new()
	root.add_child(world)
	var preview := GuardScene.instantiate() as Preview
	var prototype := preview.get_node("Playfield/Ball") as PinballBall
	prototype.set_script(Probe)
	prototype.radius = 24.0
	prototype.gravity = 1500.0
	prototype.max_speed = 3600.0
	world.add_child(preview)
	preview.set_physics_process(false)
	preview.auto_respawn = false
	var guard := preview.flippers as Guard
	guard.mode = mode as Guard.Mode
	guard.duration_ms = duration
	preview.set_ball_count(count)
	return preview


func _isolation(mode: int) -> void:
	var preview := _make_preview(mode, 40, 20)
	var guard := preview.flippers as Guard
	await physics_frame
	await physics_frame
	var right := guard.items[1] as FixedFlipper
	var points := right.world_polygon_at(right.global_transform)
	for index in 20:
		var ball := preview.balls[index]
		ball.gravity = 0.0
		var top := points[0].lerp(points[1], 0.3 + (index % 5) * 0.08)
		if index < 10:
			ball.reset_at(top + Vector2.DOWN * 20, Vector2(0, -1200))
			guard.record_shot(ball, 0.0)
		else:
			ball.reset_at(top + Vector2.UP * (ball.radius + 1), Vector2(0, 500))
			if index >= 15:
				guard.record_shot(ball, 0.0)
	preview.advance_inputs(STEP, false, false)
	for index in 20:
		var ball := preview.balls[index] as Probe
		_check(guard.is_suppressed(ball) == (index < 10), "Another ball changed suppression")
		_check(ball.velocity.y < 0, "Upward pass or downward catch failed")
		_check(ball.forbidden_contacts == 0, "Suppressed ball processed a contact")
		_check(ball.get_collision_exceptions().is_empty(), "Collision exception leaked")
	_check(guard.descent_releases == 5, "Descent did not release exactly five balls")
	# Each timer must lose one step, not one step multiplied by the ball count.
	_check(absf(guard.remaining_ms(preview.balls[0]) - (40 - STEP * 1000)) < 0.01,
		"Timer advanced with the number of balls")
	var removed := preview.balls.pop_back() as PinballBall
	guard.record_shot(removed, 0)
	var removed_id := removed.get_instance_id()
	removed.free()
	_check(not guard._states.has(removed_id), "Deleted ball retains state")
	preview.set_ball_count(1)
	_check(guard._states.is_empty(), "Reducing ball count retains state")
	preview.get_parent().free()
	await physics_frame


func _case(mode: int, duration: float, scenario: String, seed_value: int, count: int, seconds: float) -> void:
	var normal := _make_preview(mode, duration, count)
	var reverse := _make_preview(mode, duration, count)
	var reference := _make_preview(mode, duration, 1)
	var logical_reverse := reverse.balls.duplicate()
	reverse.balls.reverse()
	_configure(normal, scenario, seed_value)
	_configure(reverse, scenario, seed_value, logical_reverse)
	_configure(reference, scenario, seed_value)
	if scenario == "reflector":
		for preview: Preview in [normal, reverse, reference]:
			_add_reflector(preview)
	await physics_frame
	await physics_frame
	var below: Dictionary[int, bool] = {}
	var max_order_error := 0.0
	var max_reference_error := 0.0
	var max_reference_position_error := 0.0
	var max_reference_velocity_error := 0.0
	var reference_state_mismatches := 0
	var first_reference_difference: Dictionary = {}
	var bad_states := 0
	var invalid := 0
	var cpu_us: int = 0
	var max_zero_steps: int = 0
	var zero_steps: Dictionary[int, int] = {}
	for step_index in int(seconds / STEP):
		var time := step_index * STEP
		var cycle := fmod(time, 0.55)
		var left := cycle < 0.08
		var right := cycle < 0.08
		if scenario == "alternating":
			right = fmod(time + 0.275, 0.55) < 0.08
		var before: Array[Vector2] = []
		for target: PinballBall in normal.balls:
			before.append(target.global_position)
		var started := Time.get_ticks_usec()
		var old_reference_error := max_reference_error
		normal.advance_inputs(STEP, left, right)
		cpu_us += Time.get_ticks_usec() - started
		reverse.advance_inputs(STEP, left, right)
		reference.advance_inputs(STEP, left, right)
		var guard := normal.flippers as Guard
		var other_guard := reverse.flippers as Guard
		for index in count:
			var target := normal.balls[index] as Probe
			var other := logical_reverse[index] as Probe
			max_order_error = maxf(max_order_error, target.global_position.distance_to(other.global_position))
			max_order_error = maxf(max_order_error, target.velocity.distance_to(other.velocity))
			if guard.is_suppressed(target) != other_guard.is_suppressed(other):
				bad_states += 1
			if not is_finite(target.global_position.x) or not is_finite(target.velocity.y):
				invalid += 1
			var id := target.get_instance_id()
			var stalled := target.active and target.velocity.length() > 300 \
				and target.global_position.distance_squared_to(before[index]) < 0.000001
			zero_steps[id] = zero_steps.get(id, 0) + 1 if stalled else 0
			max_zero_steps = maxi(max_zero_steps, zero_steps[id])
			for item: PinballFlipper in guard.items:
				var fixed := item as FixedFlipper
				var floor_y := fixed.fixed_bottom + target.radius
				if before[index].y <= floor_y and target.global_position.y > floor_y:
					var fraction := (floor_y - before[index].y) / (target.global_position.y - before[index].y)
					var cross_x := lerpf(before[index].x, target.global_position.x, fraction)
					if cross_x > fixed.fixed_left + target.radius and cross_x < fixed.fixed_right - target.radius:
						below[index] = true
		max_reference_error = maxf(max_reference_error,
			normal.ball.global_position.distance_to(reference.ball.global_position))
		max_reference_error = maxf(max_reference_error,
			normal.ball.velocity.distance_to(reference.ball.velocity))
		max_reference_position_error = maxf(max_reference_position_error,
			normal.ball.global_position.distance_to(reference.ball.global_position))
		max_reference_velocity_error = maxf(max_reference_velocity_error,
			normal.ball.velocity.distance_to(reference.ball.velocity))
		if old_reference_error < 0.01 and guard.is_suppressed(normal.ball) \
			!= (reference.flippers as Guard).is_suppressed(reference.ball):
			reference_state_mismatches += 1
		if max_reference_error > 0.01 and first_reference_difference.is_empty():
			first_reference_difference = {"time": time, "many_position": normal.ball.global_position,
				"one_position": reference.ball.global_position, "many_velocity": normal.ball.velocity,
				"one_velocity": reference.ball.velocity,
				"many_contact": (normal.ball as Probe).last_native_contact,
				"one_contact": (reference.ball as Probe).last_native_contact,
				"many_native_events": (normal.ball as Probe).native_contacts_this_step,
				"one_native_events": (reference.ball as Probe).native_contacts_this_step}
		if step_index % 4 == 3:
			await physics_frame
	var guard := normal.flippers as Guard
	var totals := {"shots": 0, "forbidden_contacts": 0, "contact_limit_steps": 0,
		"other_contacts": 0, "inactive": 0, "max_separation_px": 0.0,
		"truncated_steps": 0, "discarded_ball_seconds": 0.0, "max_discarded_step_ms": 0.0}
	var capped_sources: Dictionary[String, int] = {}
	var first_cap: Dictionary = {}
	for target: Probe in normal.balls:
		totals.shots += target.shots
		totals.forbidden_contacts += target.forbidden_contacts
		totals.contact_limit_steps += target.contact_limit_steps
		totals.truncated_steps += target.truncated_steps
		totals.discarded_ball_seconds += target.discarded_seconds
		totals.max_discarded_step_ms = maxf(totals.max_discarded_step_ms,
			target.max_discarded_seconds * 1000)
		totals.other_contacts += target.other_contacts
		totals.inactive += int(not target.active)
		totals.max_separation_px = maxf(totals.max_separation_px, target.max_separation)
		for source: String in target.capped_sources:
			capped_sources[source] = capped_sources.get(source, 0) + target.capped_sources[source]
		if first_cap.is_empty() and not target.first_cap.is_empty():
			first_cap = target.first_cap
	var entry := {"mode": mode + 3, "duration_ms": duration if mode == 1 else 0.0,
		"scenario": scenario, "seed": seed_value, "balls": count, "seconds": seconds,
		"max_order_error": max_order_error, "state_mismatches": bad_states,
		"max_single_reference_error": max_reference_error, "invalid": invalid,
		"max_single_position_error_px": max_reference_position_error,
		"max_single_velocity_error_px_s": max_reference_velocity_error,
		"reference_state_mismatches_before_divergence": reference_state_mismatches,
		"first_reference_difference": first_reference_difference,
		"below_flipper_balls": below.size(), "max_zero_motion_steps": max_zero_steps,
		"descent_releases": guard.descent_releases, "time_releases": guard.time_releases,
		"mean_cpu_ms_per_60hz_tick": cpu_us / (seconds * 60.0 * 1000.0), "totals": totals,
		"capped_contact_sources": capped_sources, "first_contact_limit_step": first_cap}
	results.append(entry)
	_check(max_order_error < 0.01 and bad_states == 0, "Ball order changes another ball's state")
	var native_wall_difference := false
	if not first_reference_difference.is_empty():
		var many_contact: Dictionary = first_reference_difference.many_contact
		var one_contact: Dictionary = first_reference_difference.one_contact
		native_wall_difference = first_reference_difference.many_native_events > 0 \
			and first_reference_difference.one_native_events > 0 \
			and many_contact.collider == one_contact.collider and many_contact.collider == "Lower" \
			and (many_contact.normal as Vector2).distance_to(one_contact.normal) > 0.0001
	_check(reference_state_mismatches == 0 and (max_reference_error < 0.01 or native_wall_difference),
		"Single reference diverged without a different native-wall contact")
	_check(invalid == 0 and totals.forbidden_contacts == 0, "Invalid state or suppressed contact")
	print(JSON.stringify(entry))
	for preview: Preview in [normal, reverse, reference]:
		preview.get_parent().free()
	await physics_frame


func _configure(preview: Preview, scenario: String, seed_value: int, logical: Array = []) -> void:
	var ordered: Array = preview.balls if logical.is_empty() else logical
	for index in ordered.size():
		var target := ordered[index] as Probe
		var random := RandomNumberGenerator.new()
		random.seed = seed_value * 1000 + index
		target.radius = [6.0, 15.0, 24.0, 36.0][index % 4] if scenario == "mixed" else 24.0
		var position := Vector2(random.randf_range(610, 1310), random.randf_range(180, 760))
		var velocity := Vector2(random.randf_range(-400, 400), random.randf_range(0, 500))
		if scenario == "volley" or scenario == "reflector" or scenario == "overlap":
			var fixed := preview.flippers.items[index % 2] as FixedFlipper
			var points := fixed.world_polygon_at(fixed.global_transform)
			var ratio := 0.15 + (index / 2) % 10 * 0.075
			position = points[0].lerp(points[1], ratio) + Vector2.UP * (target.radius + 4)
			velocity = Vector2(0, 300)
			if scenario == "overlap":
				position = points[0].lerp(points[1], ratio) + Vector2.DOWN * 30
				velocity = Vector2(0, -600)
		target.reset_at(position, velocity)
		if scenario == "overlap":
			(preview.flippers as Guard).record_shot(target, 0.0)


func _add_reflector(preview: Preview) -> void:
	var body := StaticBody2D.new()
	body.name = "ReturnTestWall"
	body.position = Vector2(960, 850)
	body.collision_layer = 2
	body.collision_mask = 1
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(720, 12)
	shape.shape = rectangle
	body.add_child(shape)
	preview.get_node("Playfield").add_child(body)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
