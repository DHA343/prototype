extends SceneTree
## Run: godot --headless --path . --script tests/camera_shake_regression.gd

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _check_cue_defaults_and_composition()
	await _check_one_shot_and_master_intensity()
	await _check_sustain_release()
	print("Camera shake regression: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _check_cue_defaults_and_composition() -> void:
	var cue := CameraShakeCue.new()
	_expect(
		cue.base_strength == 0.0
			and cue.one_shot_duration == 0.0
			and cue.sustain_release_duration == 0.0
			and cue.kick_weight == 0.0
			and cue.low_noise_weight == 0.0
			and cue.high_noise_weight == 0.0,
		"New cues have no shake contribution."
	)
	var fixture := await _create_fixture()
	var camera: Camera2D = fixture[&"camera"]
	var fixture_shake: CameraShake = fixture[&"shake"]
	var request := CameraShakeRequest.new()
	request.cue = cue
	request.operation = CameraShakeRequest.Operation.PLAY
	request.impact_direction = Vector2.RIGHT
	fixture_shake.request(request)
	await process_frame
	_expect(camera.offset == Vector2.ZERO, "Default cues do not move the camera.")
	fixture[&"root"].queue_free()

	var shake := CameraShake.new()
	cue.base_strength = 0.5
	cue.kick_weight = 1.0
	var totals := CameraShake.ChannelStrengths.new()
	shake._add_contribution(cue, cue.base_strength, Vector2.RIGHT, totals)
	_expect(totals.kick_offset.x > 0.0, "WITH_IMPACT kicks in the impact direction.")

	cue.kick_direction = CameraShakeCue.KickDirection.OPPOSITE_IMPACT
	totals = CameraShake.ChannelStrengths.new()
	shake._add_contribution(cue, cue.base_strength, Vector2.RIGHT, totals)
	_expect(totals.kick_offset.x < 0.0, "OPPOSITE_IMPACT kicks against the impact direction.")

	cue.kick_weight = 0.0
	cue.low_noise_weight = 1.0
	totals = CameraShake.ChannelStrengths.new()
	shake._add_contribution(cue, cue.base_strength, Vector2.RIGHT, totals)
	_expect(
		totals.kick_offset == Vector2.ZERO and totals.low_strength > 0.0,
		"Zero kick weight leaves noise contributions active."
	)
	cue.low_noise_weight = 0.0
	cue.high_noise_weight = 1.0
	totals = CameraShake.ChannelStrengths.new()
	shake._add_contribution(cue, cue.base_strength, Vector2.RIGHT, totals)
	_expect(
		totals.low_strength == 0.0 and totals.high_strength > 0.0,
		"Zero low-noise weight leaves high-noise contributions active."
	)


func _check_one_shot_and_master_intensity() -> void:
	var fixture := await _create_fixture()
	var camera: Camera2D = fixture[&"camera"]
	var shake: CameraShake = fixture[&"shake"]
	var cue := CameraShakeCue.new()
	cue.base_strength = 0.5
	cue.one_shot_duration = 0.2
	cue.kick_weight = 1.0
	cue.low_noise_weight = 0.0
	cue.high_noise_weight = 0.0
	cue.kick_direction = CameraShakeCue.KickDirection.OPPOSITE_IMPACT
	var request := CameraShakeRequest.new()
	request.cue = cue
	request.operation = CameraShakeRequest.Operation.PLAY
	request.impact_direction = Vector2.RIGHT
	shake.master_intensity = 0.0
	shake.request(request)
	await process_frame
	_expect(camera.offset == Vector2.ZERO, "Master intensity prevents camera movement.")
	shake.master_intensity = 1.0
	await process_frame
	_expect(camera.offset.x < 0.0, "Kick is opposite to the impact direction.")
	await create_timer(0.25).timeout
	_expect(camera.offset == Vector2.ZERO, "One-shot finishes at zero offset.")
	fixture.root.queue_free()


func _check_sustain_release() -> void:
	var fixture := await _create_fixture()
	var camera: Camera2D = fixture[&"camera"]
	var shake: CameraShake = fixture[&"shake"]
	var source := Node.new()
	fixture.root.add_child(source)
	var cue := CameraShakeCue.new()
	cue.lifetime = CameraShakeCue.Lifetime.SUSTAIN
	cue.base_strength = 0.5
	cue.sustain_release_duration = 0.05
	cue.kick_weight = 1.0
	cue.low_noise_weight = 0.0
	cue.high_noise_weight = 0.0
	cue.kick_direction = CameraShakeCue.KickDirection.OPPOSITE_IMPACT
	var start_request := CameraShakeRequest.new()
	start_request.cue = cue
	start_request.operation = CameraShakeRequest.Operation.START
	start_request.source_id = source.get_instance_id()
	start_request.source_reference = weakref(source)
	start_request.impact_direction = Vector2.RIGHT
	shake.request(start_request)
	await process_frame
	_expect(camera.offset.x < 0.0, "Sustain starts without damage ticks.")
	var stop_request := CameraShakeRequest.new()
	stop_request.operation = CameraShakeRequest.Operation.STOP
	stop_request.source_id = source.get_instance_id()
	shake.request(stop_request)
	await create_timer(0.1).timeout
	_expect(camera.offset == Vector2.ZERO, "Sustain release finishes at zero offset.")
	fixture.root.queue_free()


func _create_fixture() -> Dictionary[StringName, Node]:
	var fixture_root := Node2D.new()
	var camera := Camera2D.new()
	var shake := CameraShake.new()
	root.add_child(fixture_root)
	fixture_root.add_child(camera)
	camera.add_child(shake)
	await process_frame
	return {&"root": fixture_root, &"camera": camera, &"shake": shake}


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
