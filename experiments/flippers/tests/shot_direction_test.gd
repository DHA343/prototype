extends SceneTree

const Preview = preload("res://experiments/flippers/preview.gd")
const GuardScene = preload("res://experiments/flippers/guard_preview.tscn")
const Guard = preload("res://experiments/flippers/shot_guard.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")
const Probe = preload("res://experiments/flippers/tests/trajectory_probe.gd")
const STEP: float = 1.0 / 240.0

var checks: int = 0
var failures: int = 0
var records: Array[Dictionary] = []
var followups: Array[Dictionary] = []
var _previews: Array[Preview] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for enabled: bool in [false, true]:
		_previews.append(_make_preview(enabled))
	await physics_frame
	await physics_frame
	for swing_angle: float in [18.0, 30.0, 45.0]:
		for shot_angle: float in [0.0, 20.0, 40.0, 60.0, 70.0]:
			for speed: float in [90.0, 180.0, 300.0, 600.0, 1200.0]:
				for timing: String in ["together", "ahead_20ms", "already_raised", "delay_15ms", "delay_30ms", "returning"]:
					for side in 2:
						for ratio: float in [0.90, 0.99]:
							records.append(await _case(swing_angle, shot_angle, speed, timing, side, ratio))
							if records.size() % 180 == 0:
								print("Completed parameter pairs: ", records.size())
	for swing_angle: float in [18.0, 45.0]:
		for shot_angle: float in [40.0, 60.0, 70.0]:
			for speed: float in [90.0, 180.0, 300.0, 600.0, 1200.0]:
				for timing: String in ["together", "already_raised"]:
					followups.append(await _case(swing_angle, shot_angle, speed, timing, 0, 0.99, 2.0))
	var contact_examples := await _contact_repetition()
	var output := {"checks": checks, "failures": failures, "cases": records, "followups": followups,
		"step_seconds": STEP, "radius_px": 24, "root_angle_degrees": -20,
		"contact_repetition": contact_examples}
	var file := FileAccess.open("res://experiments/flippers/evidence/shot_direction.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print("Shot direction checks: ", checks, "; failures: ", failures, "; pairs: ", records.size())
	quit(0 if failures == 0 else 1)


func _make_preview(enabled: bool) -> Preview:
	var world := SubViewport.new()
	world.size = Vector2i(1920, 1080)
	world.world_2d = World2D.new()
	root.add_child(world)
	var preview := GuardScene.instantiate() as Preview
	var target := preview.get_node("Playfield/Ball") as PinballBall
	target.set_script(Probe)
	target.radius = 24.0
	target.gravity = 1500.0
	target.max_speed = 3600.0
	(target as Probe).suppression_enabled = enabled
	world.add_child(preview)
	preview.set_physics_process(false)
	preview.auto_respawn = false
	(preview.flippers as Guard).mode = Guard.Mode.UNTIL_DESCENDING
	return preview


func _case(
	swing_angle: float, shot_angle: float, speed: float,
	timing: String, side: int, ratio: float, seconds: float = 0.25,
) -> Dictionary:
	for preview: Preview in _previews:
		var guard := preview.flippers as Guard
		guard.swing_angle = swing_angle
		guard.tip_angle = shot_angle
		guard.raise_speed = speed
		guard.reset_stats()
		preview.reset_ball()
		if timing in ["already_raised", "returning", "ahead_20ms"]:
			var advance_time := 0.02 if timing == "ahead_20ms" else swing_angle / speed
			guard.advance(advance_time, side != 0, side == 0)
			guard.advance(0, side != 0, side == 0)
		var fixed := guard.items[side] as FixedFlipper
		var polygon := fixed.world_polygon_at(fixed.global_transform)
		var fraction := ratio if side == 0 else 1.0 - ratio
		var top := polygon[0].lerp(polygon[1], fraction)
		var ball := preview.ball as Probe
		ball.reset_at(top + Vector2.UP * (ball.radius + 4), Vector2(0, 300))
		ball.first_shot.clear()
		ball.opposite_normal_changes.clear()
		ball.opposite_shots.clear()
		ball.opposite_corrections = 0
		ball.external_since_shot = 0
		ball.shots = 0
		ball.embedded_releases.clear()
	for step_index in int(seconds / STEP):
		var time := step_index * STEP
		var opposite_held := true
		if timing == "delay_15ms":
			opposite_held = time >= 0.015
		elif timing == "delay_30ms":
			opposite_held = time >= 0.03
		elif timing == "returning":
			opposite_held = false
		for preview: Preview in _previews:
			(preview.ball as Probe).simulation_time = time
			preview.advance_inputs(STEP, true if side == 0 else opposite_held,
				true if side == 1 else opposite_held)
		if step_index % 12 == 11:
			await physics_frame
	var baseline := _previews[0].ball as Probe
	var guarded := _previews[1].ball as Probe
	_check(not baseline.first_shot.is_empty() and not guarded.first_shot.is_empty(), "No first shot")
	if not baseline.first_shot.is_empty() and not guarded.first_shot.is_empty():
		_check(baseline.first_shot.velocity == guarded.first_shot.velocity, "First shot differs")
	_check(guarded.opposite_normal_changes.is_empty() and guarded.opposite_shots.is_empty(),
		"Opposite flipper changed an ascending guarded shot")
	var entry := {"swing_angle": swing_angle, "tip_angle": shot_angle, "raise_speed": speed,
		"timing": timing, "side": side, "ratio": ratio, "seconds": seconds,
		"baseline_first_shot": baseline.first_shot.duplicate(true),
		"guard_first_shot": guarded.first_shot.duplicate(true),
		"baseline_normal_changes": baseline.opposite_normal_changes.duplicate(true),
		"guard_normal_changes": guarded.opposite_normal_changes.duplicate(true),
		"baseline_opposite_shots": baseline.opposite_shots.duplicate(true),
		"guard_opposite_shots": guarded.opposite_shots.duplicate(true),
		"baseline_position_only": baseline.opposite_corrections,
		"guard_position_only": guarded.opposite_corrections,
		"guard_max_separation_px": guarded.max_separation,
		"guard_embedded_releases": guarded.embedded_releases.duplicate(true),
		"guard_descent_releases": (_previews[1].flippers as Guard).descent_releases}
	return entry


func _contact_repetition() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for raised: bool in [false, true]:
		var preview := _previews[0]
		preview.flippers.swing_angle = 18
		preview.flippers.raise_speed = 600
		preview.reset_ball()
		if raised:
			preview.flippers.advance(0.1, true, true)
			preview.flippers.advance(0, true, true)
		var ball := preview.ball as Probe
		ball.cap_trace.clear()
		ball.reset_at(Vector2(1113.424, 1004.916), Vector2(-28.08752, 4.631094))
		for step_index in 120:
			ball.simulation_time = step_index * STEP
			preview.advance_inputs(STEP, raised, raised)
			if not ball.cap_trace.is_empty():
				break
		results.append({"raised": raised, "trace": ball.cap_trace.duplicate(true)})
	return results


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
