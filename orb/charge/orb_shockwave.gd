class_name ShockwaveChargeAbility
extends ChargeAbility

var _shockwave_definition: ShockwaveChargeAbilityDefinition


func activate(charge_level: float) -> bool:
	var shockwave := _shockwave_definition.shockwave_scene.instantiate() as Shockwave
	assert(shockwave != null, "Shockwave scene root must use the Shockwave script.")

	shockwave.set_charge_level(charge_level)
	shockwave.sound_requested.connect(_orb.sound_requested.emit)
	shockwave.position = _orb.get_parent().to_local(_orb.sweep_hit.global_position)
	_orb.add_sibling(shockwave)
	return true


func _setup() -> void:
	_shockwave_definition = _definition as ShockwaveChargeAbilityDefinition
	assert(_shockwave_definition != null, "ShockwaveChargeAbility requires its matching definition.")
	assert(_shockwave_definition.shockwave_scene != null, "shockwave_scene must not be null.")


func _teardown() -> void:
	_shockwave_definition = null
