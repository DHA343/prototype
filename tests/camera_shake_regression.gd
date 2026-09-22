extends SceneTree
## Run: godot --headless --path . --script tests/camera_shake_regression.gd

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_cue_types_and_channel_independence()
	_check_scaled_channel_contributions()
	await _check_one_shot_and_master_intensity()
	await _check_sustain_release()
	print("Camera shake regression: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _check_cue_types_and_channel_independence() -> void:
	var base_cue := CameraShakeCue.new()
	_expect(
		base_cue.low_noise_strength == 0.0 and base_cue.high_noise_strength == 0.0,
		"Noise strengths default to zero."
	)
	var one_shot := OneShotCameraShakeCue.new()
	var sustain := SustainCameraShakeCue.new()
	_expect(
		one_shot.duration == 0.0 and one_shot.kick_strength == 0.0,
		"One-shot cue settings default to zero."
	)
	_expect(sustain.release_duration == 0.0, "Sustain release defaults to zero.")

	var shake := CameraShake.new()
	var state := CameraShake.OneShotState.new()
	state.cue = one_shot
	state.cue.duration = 1.0
	state.cue.kick_strength = 0.5
	state.cue.low_noise_strength = 0.2
	state.cue.high_noise_strength = 0.1
	state.impact_direction = Vector2.RIGHT
	var totals := CameraShake.ChannelStrengths.new()
	shake._add_one_shot_contribution(state, totals)
	_expect(
		is_equal_approx(totals.kick_strength, 0.5)
			and is_equal_approx(totals.low_strength, 0.2)
			and is_equal_approx(totals.high_strength, 0.1),
		"Each channel uses its own strength."
	)
	state.cue.low_noise_strength = 0.3
	totals = CameraShake.ChannelStrengths.new()
	shake._add_one_shot_contribution(state, totals)
	_expect(
		is_equal_approx(totals.kick_strength, 0.5)
			and is_equal_approx(totals.low_strength, 0.3)
			and is_equal_approx(totals.high_strength, 0.1),
		"Changing one channel does not change other channels."
	)
	shake.free()


func _check_scaled_channel_contributions() -> void:
	var shake := CameraShake.new()
	var cue := OneShotCameraShakeCue.new()
	cue.duration = 1.0
	cue.kick_strength = 0.75
	cue.low_noise_strength = 0.75
	cue.high_noise_strength = 0.25
	var state := CameraShake.OneShotState.new()
	state.cue = cue
	state.impact_direction = Vector2.RIGHT
	state.strength_scale = 2.0
	var totals := CameraShake.ChannelStrengths.new()
	shake._add_one_shot_contribution(state, totals)
	_expect(
		is_equal_approx(totals.kick_strength, 1.0)
			and is_equal_approx(totals.low_strength, 1.0)
			and is_equal_approx(totals.high_strength, 0.5),
		"One-shot channel contributions clamp after applying strength_scale."
	)

	var second_state := CameraShake.OneShotState.new()
	second_state.cue = cue
	second_state.impact_direction = Vector2.LEFT
	second_state.strength_scale = 2.0
	shake._add_one_shot_contribution(second_state, totals)
	_expect(
		is_equal_approx(totals.low_strength, 1.0)
			and totals.low_strength >= 0.0 and totals.low_strength <= 1.0,
		"Overlapping clamped noise contributions remain within the normalized range."
	)

	cue.low_noise_strength = 0.25
	var weak_state := CameraShake.OneShotState.new()
	weak_state.cue = cue
	weak_state.impact_direction = Vector2.ZERO
	weak_state.strength_scale = 2.0
	totals = CameraShake.ChannelStrengths.new()
	shake._add_one_shot_contribution(weak_state, totals)
	_expect(
		is_equal_approx(totals.low_strength, 0.5),
		"Strength scales above one still strengthen weak channel values."
	)

	var sustain_cue := SustainCameraShakeCue.new()
	sustain_cue.release_duration = 1.0
	sustain_cue.low_noise_strength = 0.75
	sustain_cue.high_noise_strength = 0.25
	var sustain := CameraShake.SustainState.new()
	sustain.cue = sustain_cue
	sustain.strength_scale = 2.0
	totals = CameraShake.ChannelStrengths.new()
	shake._add_sustain_contribution(sustain, totals)
	_expect(
		is_equal_approx(totals.low_strength, 1.0)
			and is_equal_approx(totals.high_strength, 0.5),
		"Active sustain contributions clamp after applying strength_scale."
	)

	shake._begin_release(sustain)
	totals = CameraShake.ChannelStrengths.new()
	shake._add_sustain_contribution(sustain, totals)
	_expect(
		is_equal_approx(sustain.release_scale, 2.0)
			and is_equal_approx(totals.low_strength, 1.0)
			and is_equal_approx(totals.high_strength, 0.5),
		"Release preserves the request scale and clamps channel contributions."
	)
	sustain.release_elapsed = sustain_cue.release_duration * 0.5
	totals = CameraShake.ChannelStrengths.new()
	shake._add_sustain_contribution(sustain, totals)
	_expect(
		is_equal_approx(totals.low_strength, 0.375)
			and is_equal_approx(totals.high_strength, 0.125)
			and totals.low_strength <= 1.0 and totals.high_strength <= 1.0,
		"Release envelope smoothly reduces bounded channel contributions."
	)
	shake.free()


func _check_one_shot_and_master_intensity() -> void:
	var fixture := await _create_fixture()
	var camera: Camera2D = fixture[&"camera"]
	var shake: CameraShake = fixture[&"shake"]
	var cue := OneShotCameraShakeCue.new()
	cue.duration = 0.2
	cue.kick_strength = 0.5
	cue.kick_direction = OneShotCameraShakeCue.KickDirection.OPPOSITE_IMPACT
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
	fixture[&"root"].queue_free()


func _check_sustain_release() -> void:
	var fixture := await _create_fixture()
	var camera: Camera2D = fixture[&"camera"]
	var shake: CameraShake = fixture[&"shake"]
	var source := Node.new()
	fixture[&"root"].add_child(source)
	var cue := SustainCameraShakeCue.new()
	cue.release_duration = 0.05
	cue.low_noise_strength = 0.5
	var start_request := CameraShakeRequest.new()
	start_request.cue = cue
	start_request.operation = CameraShakeRequest.Operation.START
	start_request.source_id = source.get_instance_id()
	start_request.source_reference = weakref(source)
	shake.request(start_request)
	await process_frame
	_expect(camera.offset != Vector2.ZERO, "Sustain starts with noise and no kick.")
	var update_request := CameraShakeRequest.new()
	update_request.operation = CameraShakeRequest.Operation.UPDATE
	update_request.source_id = source.get_instance_id()
	update_request.strength_scale = 0.0
	shake.request(update_request)
	await process_frame
	_expect(camera.offset == Vector2.ZERO, "Sustain UPDATE changes its strength scale.")
	var stop_request := CameraShakeRequest.new()
	stop_request.operation = CameraShakeRequest.Operation.STOP
	stop_request.source_id = source.get_instance_id()
	shake.request(stop_request)
	await create_timer(0.1).timeout
	_expect(camera.offset == Vector2.ZERO, "Sustain release finishes at zero offset.")
	var lost_source := Node.new()
	fixture[&"root"].add_child(lost_source)
	var lost_source_request := CameraShakeRequest.new()
	lost_source_request.cue = cue
	lost_source_request.operation = CameraShakeRequest.Operation.START
	lost_source_request.source_id = lost_source.get_instance_id()
	lost_source_request.source_reference = weakref(lost_source)
	shake.request(lost_source_request)
	await process_frame
	lost_source.free()
	await process_frame
	var lost_state := shake._sustains.get(lost_source_request.source_id) as CameraShake.SustainState
	_expect(
		lost_state != null and lost_state.is_releasing and lost_state.release_scale == 1.0,
		"Destroyed sources enter release at their current strength."
	)
	await create_timer(0.1).timeout
	_expect(
		not shake._sustains.has(lost_source_request.source_id),
		"Destroyed source sustain ends after release_duration."
	)
	fixture[&"root"].queue_free()


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
