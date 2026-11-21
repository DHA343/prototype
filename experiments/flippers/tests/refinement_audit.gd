extends "res://experiments/flippers/tests/continuous_response.gd"

const Refined = preload("res://experiments/flippers/refined_swing.gd")
const RefinedMotion = preload("res://experiments/flippers/refined_motion.gd")
const RefinedRecorder = preload("res://experiments/flippers/tests/refined_motion.gd")
const Continuous = preload("res://experiments/flippers/continuous_swing.gd")
const MODES: Array[int] = [0, 2, 4, 8, -1]
const COUNT_KEYS: Array[String] = ["coarse_checks", "extra_checks", "eligible", "refined",
	"no_previous", "previous_contact", "final_invalid", "stopped_state"]

var _mode: int = 0
var _original: Dictionary = {}


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	for row: Dictionary in previous.cases:
		_original[_key(row)] = row
	var detection: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	_check(detection.cases.size() == 4500, "Expected exactly 4500 detector fixtures")
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for saved: Dictionary in detection.cases:
		rows.append(_detect(saved))
		if rows.size() % 500 == 0:
			print("Refinement detection: ", rows.size(), "/4500")
			await process_frame
	_write("refinement_audit.json", {"checks": _checks, "failures": _failures, "cases": rows,
		"scope": "Same 4500 fixtures and independent references as continuous_audit; detection only"})
	var replay: Array[Dictionary] = []
	for saved: Dictionary in previous.cases:
		var results := {}
		for mode: int in MODES:
			_mode = mode
			var input: Dictionary = _inputs[int(saved.id)]
			var duration: float = 1.0 / saved.rate
			var source := _prepare(input)
			_main.ball.collision_mask = 8
			_main.flippers.pass_until_descending = true
			_main.flippers.advance(duration, not input.raised, not input.raised)
			_attach_recorder(_main.ball)
			_motion = _main.ball._motion
			_reset_body(input, _unvec(saved.start), _unvec(saved.velocity))
			var plans: Array[PinballFlipper.Swing] = []
			if source != null:
				plans.append(source)
			_main.ball.advance(duration, plans)
			results[_label(mode)] = _response(_motion as Recorder, duration, saved)
			_check(_main.ball.get_collision_exceptions().is_empty(), "Collision exclusions leaked")
		_check(_unvec(results.B.position).distance_to(_unvec(saved.sampled.frame_guard3.frame_end)) < 0.001,
			"Baseline replay position changed")
		_check(_unvec(results.B.velocity).distance_to(_unvec(saved.sampled.frame_guard3.frame_velocity)) < 0.01,
			"Baseline replay velocity changed")
		replay.append({"id": saved.id, "rate": saved.rate, "suite": saved.suite,
			"ambiguous": saved.ambiguous, "reference": saved.reference, "methods": results})
		if replay.size() % 500 == 0:
			print("Refinement response: ", replay.size(), "/2628")
			await process_frame
	var integrations := {}
	var ordering: Array[Dictionary] = []
	for mode: int in MODES:
		_mode = mode
		var integration := await _integration()
		_check(integration.population.size() == 2 and integration.near_enemy.size() == 84,
			"Integration fixture count changed")
		integrations[_label(mode)] = integration
		ordering.append_array(await _order_cases())
		print("Refinement integration: ", _label(mode))
	_main.free()
	_write("refinement_response.json", {"checks": _checks, "failures": _failures,
		"replay": replay, "integration": integrations, "ordering": ordering,
		"scope": "Production response, guard 3, separation 16, contact cap 8, native static flippers retained"})
	print("Refinement checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _detect(saved: Dictionary) -> Dictionary:
	var fixture := _fixture(saved)
	var source: PinballFlipper.Swing = fixture.source
	var before := _main.ball.global_position
	var before_velocity := _main.ball.velocity
	var outputs := {}
	for mode: int in MODES:
		var swing := _candidate(source, mode)
		var hit := swing.sweep(fixture.start, fixture.velocity, fixture.radius,
			0.0, fixture.duration, _main.flippers.power_equalization)
		var packed := _pack_hit(hit, fixture.velocity)
		if packed.found and saved.reference.found:
			packed["time_error_ms"] = absf(packed.time_ms - saved.reference.time_ms)
			packed["point_error_px"] = _unvec(packed.point).distance_to(_unvec(saved.reference.point))
			packed["normal_error_deg"] = absf(rad_to_deg(
				_unvec(packed.normal).angle_to(_unvec(saved.reference.normal))))
		packed["counts"] = _counts(swing)
		outputs[_label(mode)] = packed
		if mode == 0:
			var control := source.sweep(fixture.start, fixture.velocity, fixture.radius,
				0.0, fixture.duration, _main.flippers.power_equalization)
			var expected := _pack_hit(control, fixture.velocity)
			_check(expected.found == packed.found and expected.shot == packed.shot,
				"Instrumented B changed detection")
			if expected.found and packed.found:
				_check(absf(expected.time_ms - packed.time_ms) < 0.00001,
					"Instrumented B changed contact time")
			_check(packed.found == saved.baseline.found and packed.shot == saved.baseline.shot,
				"Saved B detection differs")
	_check(_main.ball.global_position == before and _main.ball.velocity == before_velocity,
		"Detection changed body state")
	var row := {"suite": saved.suite, "id": saved.id, "rate": saved.rate,
		"ambiguous": saved.ambiguous, "reference": saved.reference, "methods": outputs}
	if saved.has("case"):
		row["case"] = saved.case
	return row


func _fixture(saved: Dictionary) -> Dictionary:
	var source: PinballFlipper.Swing
	var input: Dictionary
	if saved.suite == "moving_edges":
		input = saved.case
		_set_pose(input.angle)
		var item := _main.flippers.items[int(input.side)] as TableFlipper
		source = item.plan_motion(input.angle == 0.0, 18.0, 600.0 if input.angle == 0.0 else 420.0)
	else:
		input = _original[_key(saved)]
		source = _prepare(_inputs[int(saved.id)])
	return {"source": source, "start": _unvec(input.start),
		"velocity": _unvec(input.velocity).limit_length(3600.0),
		"radius": input.radius, "duration": 1.0 / saved.rate}


func _candidate(source: PinballFlipper.Swing, mode: int) -> PinballFlipper.Swing:
	var swing: PinballFlipper.Swing = Continuous.new() if mode < 0 else Refined.new()
	for property: String in ["flipper", "start_angle", "speed", "stop_time", "parent_pose", "origin", "reach"]:
		swing.set(property, source.get(property))
	if mode >= 0:
		swing.set("iterations", mode)
	return swing


func _pack_hit(hit: Dictionary, velocity: Vector2) -> Dictionary:
	if hit.is_empty():
		return {"found": false, "shot": false}
	return {"found": true,
		"shot": hit.is_striking and (velocity - (hit.surface_velocity as Vector2)).dot(hit.normal) < 0.0,
		"time_ms": hit.time * 1000.0, "point": _vec(hit.point), "normal": _vec(hit.normal),
		"depth": hit.depth, "surface_velocity": _vec(hit.surface_velocity),
		"ratio": hit.ratio, "is_striking": hit.is_striking}


func _counts(swing: PinballFlipper.Swing) -> Dictionary:
	var counts := {}
	if swing is Refined:
		for key: String in COUNT_KEYS:
			counts[key] = swing.get(key)
	else:
		counts = {"evaluations": swing.get("evaluations"), "unresolved": swing.get("unresolved")}
	return counts


func _attach_recorder(ball: PinballBall) -> void:
	var recorder: Recorder
	if _mode == 0:
		recorder = Recorder.new(ball)
	elif _mode < 0:
		recorder = ContinuousMotion.new(ball)
	else:
		recorder = RefinedRecorder.new(ball)
		recorder.set("iterations", _mode)
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _integration_modes() -> Array[bool]:
	return [false] if _mode == 0 else [true]


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	if recorder is RefinedRecorder:
		if not result.has("search_counts"):
			result["search_counts"] = {}
		for key: String in COUNT_KEYS:
			result.search_counts[key] = result.search_counts.get(key, 0) + recorder.search_counts.get(key, 0)


func _response(recorder: Recorder, duration: float, saved: Dictionary) -> Dictionary:
	var result := {"position": _vec(recorder.body.global_position), "velocity": _vec(recorder.body.velocity),
		"contacts": recorder.events.size(), "discarded_ms": recorder.discarded_seconds * 1000.0,
		"shots": 0, "max_correction": 0.0, "unresolved": 0}
	for event: Dictionary in recorder.events:
		result.shots += int(event.shot)
		result.max_correction = maxf(result.max_correction, event.correction_px)
	result["first"] = recorder.events[0].duplicate(true) if not recorder.events.is_empty() else {
		"found": false, "shot": false, "end": _vec(_unvec(saved.start) + _unvec(saved.velocity) * duration),
		"velocity": saved.velocity, "correction_px": 0.0}
	if recorder.discarded_seconds > 0.0:
		result["cap_trace"] = recorder.events.duplicate(true)
	if recorder is ContinuousMotion:
		result.unresolved = recorder.unresolved
	elif recorder is RefinedRecorder:
		result["search_counts"] = recorder.search_counts.duplicate()
	return result


func _order_cases() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for kind: String in ["wall", "enemy"]:
		for difference: float in [-0.002, -0.0001, 0.0, 0.0001, 0.002]:
			_reset_integration()
			_main.ball.gravity = 0.0
			var item := _main.flippers.items[0] as TableFlipper
			var points := item.world_polygon_at(item.global_transform)
			var edge := points[1] - points[0]
			var normal := Vector2(edge.y, -edge.x).normalized()
			var start := points[0].lerp(points[1], 0.65) + normal * 30.0
			var incoming := Vector2(600, 1200) if kind == "wall" else Vector2(600, -600)
			var plans := _main.flippers.plan_motion(true, false)
			var reference := _oracle(item, plans[0], item.global_transform,
				start, incoming, 24.0, 1.0 / 60.0)
			_check(not reference.hit.is_empty(), "Ordering fixture has no flipper contact")
			if reference.hit.is_empty():
				continue
			var plate_time: float = reference.hit.time
			var obstacle_time := plate_time + difference
			_check(obstacle_time > 0.0, "Ordering fixture starts overlapping")
			var obstacle: PhysicsBody2D
			if kind == "wall":
				obstacle = StaticBody2D.new()
				obstacle.name = "OrderWall"
				obstacle.collision_layer = 2
				var collision := CollisionShape2D.new()
				var rectangle := RectangleShape2D.new()
				rectangle.size = Vector2(6, 200)
				collision.shape = rectangle
				obstacle.add_child(collision)
				_main.get_node("Playfield").add_child(obstacle)
				obstacle.global_position = Vector2(start.x + incoming.x * obstacle_time + 27.0, start.y)
			else:
				var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
				enemy.name = "OrderEnemy"
				enemy.death_cue = null
				_main.get_node("Playfield").add_child(enemy)
				enemy.global_position = start + incoming * obstacle_time + incoming.normalized() * 54.0
				enemy.prepare(enemy.grow_duration)
				obstacle = enemy
			obstacle.force_update_transform()
			_main.ball.reset_at(start, incoming)
			await physics_frame
			_main.flippers.advance(1.0 / 60.0, true, false)
			_main.ball.advance(1.0 / 60.0, plans)
			var recorder := _main.ball._motion as Recorder
			_check(not recorder.events.is_empty(), "Ordering contact was not processed")
			rows.append({"mode": _label(_mode), "kind": kind, "difference_ms": difference * 1000.0,
				"reference_plate_ms": plate_time * 1000.0, "reference_other_ms": obstacle_time * 1000.0,
				"tie_band": absf(difference) < 0.0002,
				"reference_first": str(obstacle.name) if difference < 0.0 else "LeftFlipper",
				"first": recorder.events[0].target if not recorder.events.is_empty() else "none",
				"events": recorder.events.duplicate(true),
				"discarded_ms": recorder.discarded_seconds * 1000.0})
			if is_instance_valid(obstacle):
				obstacle.free()
	return rows


func _key(row: Dictionary) -> String:
	return "%s:%s" % [int(row.id), int(row.rate)]


func _label(mode: int) -> String:
	return "D2" if mode < 0 else ("B" if mode == 0 else "B+%s" % mode)


func _write(filename: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://experiments/flippers/evidence/" + filename, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
