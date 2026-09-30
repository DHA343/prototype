class_name HomingMissileChargeAbility
extends ChargeAbility

var _missile_definition: HomingMissileDefinition


func activate(charge_level: float) -> bool:
	var missile_count := _missile_definition.get_missile_count(charge_level)
	var angle_offset := randf_range(0.0, TAU)

	for index in missile_count:
		var missile := _missile_definition.missile_scene.instantiate() as HomingMissile
		assert(missile != null, "missile_scene root must use the HomingMissile script.")

		var angle := angle_offset + TAU * float(index) / float(missile_count)
		missile.configure(Vector2.from_angle(angle), _missile_definition)
		# Spawned missiles outlive the equipped ability and the Orb.
		missile.sound_requested.connect(_request_sound)
		var spawn_position: Vector2 = _get_spawn_position.call()
		missile.position = _spawn_parent.to_local(spawn_position)
		_spawn_parent.add_child(missile)

	if _missile_definition.activation_cue != null:
		var sound_position: Vector2 = _get_sound_position.call()
		sound_requested.emit(SoundRequest.new(_missile_definition.activation_cue, sound_position, self))

	return true


func _setup() -> void:
	_missile_definition = _definition as HomingMissileDefinition
	assert(_missile_definition != null, "HomingMissileChargeAbility requires its matching definition.")
	assert(_missile_definition.missile_scene != null, "missile_scene must not be null.")
	assert(
		_missile_definition.min_missile_count <= _missile_definition.max_missile_count,
		"min_missile_count must not exceed max_missile_count."
	)


func _teardown() -> void:
	_missile_definition = null
