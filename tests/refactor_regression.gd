extends SceneTree
## Run: godot --headless --path . --script tests/refactor_regression.gd

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Let startup finish before testing frame-based aggregation and audio playback.
	await process_frame
	await process_frame
	_check_health()
	_check_hit_feedback()
	_check_crowd_lifecycle()
	_check_effect_parameters()
	await _check_audio()
	await process_frame
	print("Refactor regression: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _check_health() -> void:
	var health := Health.new()
	var events: Array[String] = []
	health.health_changed.connect(func(_current: float, _maximum: float): events.append("changed"))
	health.died.connect(func(): events.append("died"))
	root.add_child(health)
	_expect(health.current_health == 100.0 and events.is_empty(), "Initial health is silent.")
	health.take_damage(40.0)
	_expect(health.current_health == 60.0, "Damage reduces health.")
	health.heal(10.0)
	_expect(health.current_health == 70.0, "Healing restores health.")
	health.set_max_health(50.0)
	_expect(health.current_health == 50.0, "Lower maximum clamps current health.")
	_expect(events.size() == 3, "Each health operation emits once.")
	events.clear()
	health.take_damage(80.0)
	_expect(events == ["changed", "died"], "Lethal damage notifies health before death.")
	health.take_damage(80.0)
	_expect(events.size() == 2, "Further damage at zero health is ignored.")
	health.reset()
	_expect(health.current_health == 50.0 and events.size() == 3, "Reset restores the maximum.")
	health.free()


func _check_hit_feedback() -> void:
	var scene: PackedScene = load("res://enemy/enemy.tscn")
	var enemy := scene.instantiate() as Enemy
	var events: Array[String] = []
	var damages: Array[float] = []
	var velocities: Array[Vector2] = []
	root.add_child(enemy)
	enemy.knockback_resistance = 0.25
	enemy.died.connect(func(_enemy: Enemy): events.append("died"))
	enemy.damaged.connect(func(damage: float, _position: Vector2, velocity: Vector2):
		events.append("damaged")
		damages.append(damage)
		velocities.append(velocity)
	)
	var hit := HitData.new()
	hit.damage = 40.0
	hit.knockback = 1000.0
	hit.hit_direction = Vector2(2.0, 0.0)
	enemy.hurtbox.receive_hit(hit)
	_expect(velocities[0] == Vector2(750.0, 0.0), "Direction and resistance affect knockback.")
	hit.damage = 80.0
	enemy.hurtbox.receive_hit(hit)
	_expect(events == ["damaged", "died", "damaged"], "Lethal-hit feedback follows death.")
	_expect(damages == [40.0, 80.0], "Feedback reports attack damage, including overkill.")
	_expect(velocities[1] == Vector2(1200.0, 0.0), "Feedback uses capped accumulated knockback.")


func _check_crowd_lifecycle() -> void:
	var crowd := CrowdManager.new()
	var member := Node2D.new()
	var settings := CrowdSettings.new()
	root.add_child(crowd)
	root.add_child(member)
	crowd.register_member(member, settings)
	crowd.register_member(member, settings)
	_expect(member.get_signal_connection_list("tree_exiting").size() == 1, "Registration is idempotent.")
	crowd.unregister_member(member)
	_expect(member.get_signal_connection_list("tree_exiting").is_empty(), "Unregister disconnects cleanup.")
	crowd.register_member(member, settings)
	root.remove_child(member)
	_expect(member.get_signal_connection_list("tree_exiting").is_empty(), "Tree exit unregisters members.")
	member.free()
	crowd.free()


func _check_effect_parameters() -> void:
	var effect := Blur.new()
	var material := ShaderMaterial.new()
	material.shader = effect.get_shader()
	effect.radius = 7.0
	effect.strength = 0.3
	effect.apply_to(material)
	_expect(is_equal_approx(material.get_shader_parameter("radius"), 7.0), "Effect applies radius.")
	effect.radius = 2.0
	effect.apply_to(material)
	_expect(is_equal_approx(material.get_shader_parameter("radius"), 2.0), "Effect refreshes parameters.")
	_expect(RenderLayers.WORLD_EFFECTS < RenderLayers.WORLD_UI, "World effects precede world UI.")
	_expect(RenderLayers.WORLD_UI < RenderLayers.COMPOSITE_EFFECTS, "Composite effects follow world UI.")


func _check_audio() -> void:
	var output := WorldSoundOutput.new()
	output.initial_pool_size = 2
	output.max_voices = 2
	root.add_child(output)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 44100
	var samples := PackedByteArray()
	samples.resize(88200)
	stream.data = samples
	var cue := SoundCue.new()
	cue.stream = stream
	cue.bus = &"Master"
	cue.max_instances = 1
	var first_source := RefCounted.new()
	var second_source := RefCounted.new()
	output.request(SoundRequest.new(cue, Vector2.ZERO, first_source))
	output.request(SoundRequest.new(cue, Vector2.ONE, first_source))
	_expect(output.get_pending_aggregation_count() == 1, "Same-source sound requests aggregate.")
	output.request(SoundRequest.new(cue, Vector2.ZERO, second_source))
	_expect(output.get_pending_aggregation_count() == 2, "Different sources remain independent.")
	await create_timer(0.05).timeout
	_expect(output.get_active_voice_count() == 1, "Cue limit admits one active voice.")
	_expect(output.get_cue_limit_drop_count() == 1, "Cue limit drops the second voice.")
	await create_timer(1.2).timeout
	_expect(output.get_active_voice_count() == 0, "Finished voices release their cue ownership.")
	_expect(output.get_allocated_voice_count() == 2, "Voice pool retains its allocated players.")
	output.free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
