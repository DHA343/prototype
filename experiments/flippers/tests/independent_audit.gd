extends "res://experiments/flippers/tests/native_audit.gd"

const Contact = preload("res://experiments/flippers/contact.gd")
const IndependentMotion = preload("res://experiments/flippers/tests/independent_motion.gd")
const CustomMotion = preload("res://experiments/flippers/motion.gd")

var _full_custom: bool = false
var _detection_rows: Array[Dictionary] = []
var _recovery_rows: Array[Dictionary] = []
var _response_rows: Array[Dictionary] = []
var _smoke: bool = false


func _run() -> void:
	_smoke = "--smoke" in OS.get_cmdline_user_args()
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	_make_main(false)
	await physics_frame
	await physics_frame
	_check(_main.flippers.items[0].length > 100.0, "Flipper sockets are not configured")
	var fixtures := _static_cases(false)
	var overlaps := _static_cases(true)
	for index in mini(fixtures.size(), 16) if _smoke else fixtures.size():
		_detection_rows.append(_detection_case(fixtures[index]))
		if index % 120 == 0:
			print("Independent detection: ", index, "/", fixtures.size())
			await process_frame
	for index in mini(overlaps.size(), 16) if _smoke else overlaps.size():
		_recovery_rows.append(_recovery_case(overlaps[index]))
	for index in mini(saved.cases.size(), 24) if _smoke else saved.cases.size():
		_response_rows.append(_replay(saved.cases[index]))
		if index % 300 == 0:
			print("Independent replay: ", index, "/", saved.cases.size())
			await process_frame
	var integration := {} if _smoke else await _integration()
	if not _smoke:
		_check(integration.get("population", []).size() == 4, "Population comparison did not finish")
		_check(integration.get("near_enemy", []).size() == 168, "Near-enemy comparison did not finish")
	var transitions := _transitions()
	var ordering := await _wall_order()
	var timing := [] if _smoke else _benchmark_independent()
	_main.free()
	var path := "res://_temp/independent_smoke.json" if _smoke else "res://experiments/flippers/evidence/independent_audit.json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"godot_version": Engine.get_version_info(), "detection": _detection_rows,
		"recovery": _recovery_rows, "replay": _response_rows,
		"integration": integration, "transitions": transitions, "ordering": ordering,
		"benchmark": timing,
		"custom_static": "same generic polygon and existing 4px sampler; no refinement",
		"recovery_policy": "B native on stationary / upward16 on rotating; Bprime upward16 on all flippers",
		"scope": "experimental B/Bprime; production response, guard and contact cap unchanged"}, "\t"))
	print("Independent audit checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _set_pose(angle: float) -> void:
	_main.flippers.reset_input()
	_main.flippers.swing_angle = 18.0
	_main.flippers.raise_speed = 600.0
	_main.flippers.return_speed = 420.0
	_main.flippers.pass_until_descending = false
	if angle > 0.0:
		_main.flippers.advance(angle / 600.0, true, true)
	for item: PinballFlipper in _main.flippers.items:
		item.angular_velocity = 0.0
		item.collision_layer = 8 << item.side


func _static_cases(overlapping: bool) -> Array[Dictionary]:
	var cases: Array[Dictionary] = []
	for angle: float in [0.0, 18.0]:
		_set_pose(angle)
		for side: int in 2:
			var item := _main.flippers.items[side] as TableFlipper
			var points := item.world_polygon_at(item.global_transform)
			for radius: float in [6.0, 24.0, 36.0]:
				for feature in 8:
					var edge := feature % 4
					var point := points[edge].lerp(points[(edge + 1) % 4], 0.5)
					var normal := Vector2((points[(edge + 1) % 4] - points[edge]).y,
						-(points[(edge + 1) % 4] - points[edge]).x).normalized()
					if feature >= 4:
						point = points[edge]
						var previous := points[edge] - points[(edge + 3) % 4]
						normal = (normal + Vector2(previous.y, -previous.x).normalized()).normalized()
					var base := {"angle": angle, "side": side, "radius": radius, "feature": feature}
					if overlapping:
						for depth: float in [0.2, 3.0, radius + 12.0]:
							var input := base.duplicate()
							input.merge({"depth": depth, "start": _vec(point + normal * (radius - depth)),
								"velocity": [0.0, 0.0], "rate": 60.0})
							cases.append(input)
						continue
					for rate: float in [30.0, 60.0, 120.0]:
						for gap: float in [0.2, 12.0]:
							for speed: float in [300.0, 3600.0]:
								var input := base.duplicate()
								input.merge({"case": "approach", "rate": rate,
									"start": _vec(point + normal * (radius + gap)),
									"velocity": _vec(-normal * speed)})
								cases.append(input)
						for speed: float in [0.0, 600.0]:
							var input := base.duplicate()
							input.merge({"case": "away_or_still", "rate": rate,
								"start": _vec(point + normal * (radius + 0.2)),
								"velocity": _vec(normal * speed)})
							cases.append(input)
						if feature >= 4:
							for depth: float in [-0.2, 0.2]:
								var tangent := Vector2(-normal.y, normal.x)
								var input := base.duplicate()
								input.merge({"case": "grazing", "rate": rate,
									"start": _vec(point + normal * (radius - depth) - tangent * (1800.0 / rate)),
									"velocity": _vec(tangent * 3600.0)})
								cases.append(input)
	return cases


func _detection_case(input: Dictionary) -> Dictionary:
	_set_pose(input.angle)
	_main.ball.collision_mask = 8 << int(input.side)
	var item := _main.flippers.items[int(input.side)] as TableFlipper
	var start := _unvec(input.start)
	var incoming := _unvec(input.velocity)
	var duration: float = 1.0 / input.rate
	_reset_body(input, start, incoming)
	var pose := item.global_transform
	var oracle := _oracle(item, null, pose, start, incoming, input.radius, duration)
	_check(oracle.density_delta_ms < 0.01, "Static reference is unstable")
	var reference := _packed({"state": "none" if oracle.hit.is_empty() else "contact", "hit": oracle.hit})
	var mixed := _probe(item, null, start, incoming, input.radius, duration, false)
	var custom := _probe(item, null, start, incoming, input.radius, duration, true)
	for result: Dictionary in [mixed, custom]:
		if result.state != "none" and reference.state != "none":
			result["time_error_ms"] = absf(result.time_ms - reference.time_ms)
			result["point_error_px"] = _unvec(result.point).distance_to(_unvec(reference.point))
			result["normal_error_deg"] = absf(rad_to_deg(_unvec(result.normal).angle_to(_unvec(reference.normal))))
	var row := input.duplicate()
	row.merge({"reference": reference, "mixed": mixed, "custom": custom,
		"min_gap_px": oracle.min_gap, "ambiguous": absf(oracle.min_gap) < 0.1})
	if mixed.state != custom.state and not row.ambiguous:
		row["response"] = _static_response(input)
	return row


func _static_response(input: Dictionary) -> Dictionary:
	var outputs := {}
	for custom: bool in [false, true]:
		_set_pose(input.angle)
		_main.ball.collision_mask = 8 << int(input.side)
		_full_custom = custom
		_attach_recorder(_main.ball)
		_motion = _main.ball._motion
		_reset_body(input, _unvec(input.start), _unvec(input.velocity))
		_main.ball.advance(1.0 / input.rate)
		var recorder := _main.ball._motion as Recorder
		outputs["custom" if custom else "mixed"] = {"position": _vec(_main.ball.global_position),
			"velocity": _vec(_main.ball.velocity), "events": recorder.events.duplicate(true),
			"discarded_ms": recorder.discarded_seconds * 1000.0}
	return outputs


func _probe(
	item: TableFlipper, swing: PinballFlipper.Swing, start: Vector2,
	incoming: Vector2, radius: float, duration: float, custom: bool,
) -> Dictionary:
	var before := _main.ball.global_position
	var before_velocity := _main.ball.velocity
	var result := {}
	if custom or swing != null:
		result = _packed(Contact.query(item, swing, start, incoming, radius, duration,
			_main.flippers.power_equalization))
	else:
		var motion := incoming * duration
		var collision := _main.ball.move_and_collide(motion, true, 0.03, true)
		result = {"state": "none"}
		if collision != null:
			var fraction := 0.0
			if motion.length_squared() > 0.000001:
				fraction = clampf(collision.get_travel().dot(motion) / motion.length_squared(), 0.0, 1.0)
			var initial := _gap(start, radius, item.world_polygon_at(item.global_transform))
			result = {"state": "initial_overlap" if initial < -0.0001 else "contact",
				"time_ms": duration * fraction * 1000.0, "point": _vec(collision.get_position()),
				"normal": _vec(collision.get_normal()), "travel": _vec(collision.get_travel())}
	_check(_main.ball.global_position == before and _main.ball.velocity == before_velocity,
		"Detection probe changed body position or velocity")
	return result


func _packed(result: Dictionary) -> Dictionary:
	if result.hit.is_empty():
		return {"state": "none"}
	var hit: Dictionary = result.hit
	return {"state": result.state, "time_ms": hit.time * 1000.0,
		"point": _vec(hit.point), "normal": _vec(hit.normal), "depth": hit.depth}


func _recovery_case(input: Dictionary) -> Dictionary:
	_set_pose(input.angle)
	_main.ball.collision_mask = 8 << int(input.side)
	var item := _main.flippers.items[int(input.side)] as TableFlipper
	var start := _unvec(input.start)
	_reset_body(input, start, Vector2.ZERO)
	var gap := _gap(start, input.radius, item.world_polygon_at(item.global_transform))
	_check(gap < -0.1, "Recovery fixture is not clearly overlapping")
	var mixed := _probe(item, null, start, Vector2.ZERO, input.radius, 1.0 / 60.0, false)
	var custom := _probe(item, null, start, Vector2.ZERO, input.radius, 1.0 / 60.0, true)
	var outcomes := {}
	for mode: String in ["native", "upward"]:
		_reset_body(input, start, Vector2.ZERO)
		var steps: Array[Dictionary] = []
		for iteration in 8:
			var offset := Vector2.ZERO
			if mode == "native":
				var collision := _main.ball.move_and_collide(Vector2.ZERO, true, 0.03, true)
				if collision != null:
					offset = collision.get_travel()
			else:
				offset = Vector2.UP * item.upward_separation(_main.ball.global_position,
					input.radius, item.global_transform, 0.15)
			_main.ball.global_position += offset
			_main.ball.force_update_transform()
			var after := _gap(_main.ball.global_position, input.radius,
				item.world_polygon_at(item.global_transform))
			steps.append({"offset": _vec(offset), "gap_after": after})
			if after >= -0.0001 or offset.length_squared() < 0.000000000001:
				break
		outcomes[mode] = {"steps": steps, "total_offset": _vec(_main.ball.global_position - start),
			"distance": _main.ball.global_position.distance_to(start),
			"first_distance": _unvec(steps[0].offset).length(),
			"remaining_overlap": steps.back().gap_after < -0.0001}
	_reset_body(input, start, Vector2.ZERO)
	var unreported := _main.ball.move_and_collide(Vector2.ZERO, false, 0.03, false)
	var row := input.duplicate()
	row.merge({"gap_before": gap, "mixed": mixed, "custom": custom,
		"recovery": outcomes, "flag_false_reported": unreported != null,
		"flag_false_offset": _vec(_main.ball.global_position - start)})
	return row


func _replay(saved: Dictionary) -> Dictionary:
	var input: Dictionary = _inputs[int(saved.id)]
	var duration: float = 1.0 / saved.rate
	var start := _unvec(saved.start)
	var incoming := _unvec(saved.velocity)
	var swing := _prepare(input)
	_main.ball.collision_mask = 8
	var item := _main.flippers.items[0] as TableFlipper
	_main.flippers.advance(duration, not input.raised, not input.raised)
	_reset_body(input, start, incoming)
	var mixed_probe := _probe(item, swing, start, incoming, input.radius, duration, false)
	var custom_probe := _probe(item, swing, start, incoming, input.radius, duration, true)
	if swing != null:
		_check(mixed_probe == custom_probe, "Rotating detection changed between B and Bprime")
	var outputs := {}
	for custom: bool in [false, true]:
		swing = _prepare(input)
		_main.flippers.pass_until_descending = true
		_main.flippers.advance(duration, not input.raised, not input.raised)
		_full_custom = custom
		_attach_recorder(_main.ball)
		_motion = _main.ball._motion
		_reset_body(input, start, incoming)
		var plans: Array[PinballFlipper.Swing] = []
		if swing != null:
			plans.append(swing)
		_main.ball.advance(duration, plans)
		var recorder := _motion as Recorder
		var output := {"end": _vec(_main.ball.global_position), "velocity": _vec(_main.ball.velocity),
			"contacts": recorder.events.size(), "discarded_ms": recorder.discarded_seconds * 1000.0,
			"shots": 0, "max_correction": 0.0}
		for event: Dictionary in recorder.events:
			output.shots += int(event.shot)
			output.max_correction = maxf(output.max_correction, event.correction_px)
			if custom:
				_check(not (event.kind == "native" and "Flipper" in event.target),
					"Independent flipper leaked into native collision")
		if recorder.discarded_seconds > 0.0:
			output["cap_trace"] = recorder.events.duplicate(true)
		outputs["custom" if custom else "mixed"] = output
		_check(_main.ball.get_collision_exceptions().is_empty(), "Bprime collision exclusions leaked")
		_check(_main.ball.global_position.is_finite() and _main.ball.velocity.is_finite(), "Invalid response")
	_check(_unvec(outputs.mixed.end).distance_to(_unvec(saved.sampled.frame_guard3.frame_end)) < 0.001,
		"Current B position differs from previous production audit")
	_check(_unvec(outputs.mixed.velocity).distance_to(_unvec(saved.sampled.frame_guard3.frame_velocity)) < 0.01,
		"Current B velocity differs from previous production audit")
	return {"id": saved.id, "suite": saved.suite, "rate": saved.rate, "moving": swing != null,
		"ambiguous": saved.ambiguous, "reference": saved.reference,
		"mixed_probe": mixed_probe, "custom_probe": custom_probe,
		"mixed": outputs.mixed, "custom": outputs.custom,
		"position_delta": _unvec(outputs.mixed.end).distance_to(_unvec(outputs.custom.end)),
		"velocity_delta": _unvec(outputs.mixed.velocity).distance_to(_unvec(outputs.custom.velocity))}


func _select_integration_mode(custom: bool) -> void:
	_full_custom = custom


func _integration_swings(
	swings: Array[PinballFlipper.Swing], _sampled: bool,
) -> Array[PinballFlipper.Swing]:
	return swings


func _attach_recorder(ball: PinballBall) -> void:
	var recorder := IndependentMotion.new(ball) if _full_custom else Recorder.new(ball)
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _transitions() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for custom: bool in [false, true]:
		for kind: String in ["release_rest", "release_held", "release_rising", "stop_now", "stop_next"]:
			_full_custom = custom
			_reset_integration()
			var item := _main.flippers.items[0] as TableFlipper
			if kind.begins_with("release"):
				if kind == "release_held":
					_main.flippers.advance(18.0 / 600.0, true, false)
				var polygon := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(polygon[0].lerp(polygon[1], 0.65) + Vector2.DOWN * 12.0,
					Vector2(0, -1))
				_main.flippers.disable_target(_main.ball)
			else:
				_main.flippers.advance(15.0 / 600.0, true, false)
				var polygon := item.world_polygon_at(item.global_transform)
				_main.ball.reset_at(polygon[0].lerp(polygon[1], 0.65) + Vector2.UP * 28,
					Vector2(0, 600))
				if kind == "stop_next":
					_main.flippers.advance(3.0 / 600.0, true, false)
			var pressed := kind != "release_rest"
			var plans := _main.flippers.plan_motion(pressed, false)
			_main.flippers.advance(1.0 / 60.0, pressed, false)
			var was_disabled := _main.flippers.is_target_disabled(_main.ball.get_instance_id())
			_main.ball.advance(1.0 / 60.0, plans)
			var recorder := _main.ball._motion as Recorder
			rows.append({"custom": custom, "case": kind, "start_disabled": was_disabled,
				"moving": not plans.is_empty(), "position": _vec(_main.ball.global_position),
				"velocity": _vec(_main.ball.velocity), "discarded_ms": recorder.discarded_seconds * 1000,
				"disabled": _main.flippers.is_target_disabled(_main.ball.get_instance_id()),
				"events": recorder.events.duplicate(true)})
			_check(_main.ball.global_position.is_finite(), "Invalid recovery transition")
	return rows


func _wall_order() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for custom: bool in [false, true]:
		for difference: float in [-0.002, -0.0001, 0.0, 0.0001, 0.002]:
			_full_custom = custom
			_reset_integration()
			_main.ball.gravity = 0.0
			var item := _main.flippers.items[0] as TableFlipper
			var polygon := item.world_polygon_at(item.global_transform)
			var edge := polygon[1] - polygon[0]
			var normal := Vector2(edge.y, -edge.x).normalized()
			var start := polygon[0].lerp(polygon[1], 0.65) + normal * 30.0
			var incoming := Vector2(600, 1200)
			var plate_time := 6.0 / -incoming.dot(normal)
			var wall_time := plate_time + difference
			var wall := StaticBody2D.new()
			wall.name = "OrderWall"
			wall.collision_layer = 2
			var collision := CollisionShape2D.new()
			var rectangle := RectangleShape2D.new()
			rectangle.size = Vector2(6, 200)
			collision.shape = rectangle
			wall.add_child(collision)
			_main.get_node("Playfield").add_child(wall)
			wall.global_position = Vector2(start.x + incoming.x * wall_time + 27.0, start.y)
			wall.force_update_transform()
			_main.ball.reset_at(start, incoming)
			await physics_frame
			_main.ball.advance(1.0 / 60.0)
			var recorder := _main.ball._motion as Recorder
			_check(not recorder.events.is_empty(), "Wall-order fixture found no contact")
			rows.append({"custom": custom, "difference_ms": difference * 1000.0,
				"reference_plate_ms": plate_time * 1000.0, "reference_wall_ms": wall_time * 1000.0,
				"tie_band": absf(difference) < 0.0002,
				"reference_first": "OrderWall" if difference < 0.0 else "LeftFlipper",
				"first": recorder.events[0].target, "events": recorder.events.duplicate(true),
				"position": _vec(_main.ball.global_position), "velocity": _vec(_main.ball.velocity),
				"discarded_ms": recorder.discarded_seconds * 1000.0})
			wall.free()
	return rows


func _benchmark_independent() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for run in 8:
		for custom: bool in ([false, true] if run % 2 == 0 else [true, false]):
			var total := 0
			var motion := CustomMotion.new(_main.ball) if custom else PinballMotion.new(_main.ball)
			motion.native_contact = _main.ball._resolve_contact
			motion.contact_recorded = _main.ball._record_contact
			_main.ball._motion = motion
			_motion = motion
			_main.ball.gravity = 0.0
			_main.ball.max_speed = 3600.0
			_main.ball.collision_mask = 8
			for input: Dictionary in _inputs:
				var swing := _prepare(input)
				_main.flippers.pass_until_descending = true
				_main.flippers.advance(1.0 / 60.0, not input.raised, not input.raised)
				_reset_body(input, _unvec(input.start), _unvec(input.velocity).limit_length(3600.0))
				var plans: Array[PinballFlipper.Swing] = []
				if swing != null:
					plans.append(swing)
				var began := Time.get_ticks_usec()
				_main.ball.advance(1.0 / 60.0, plans)
				total += Time.get_ticks_usec() - began
			if run > 0:
				rows.append({"run": run, "custom": custom, "inputs": _inputs.size(), "total_us": total})
	return rows
