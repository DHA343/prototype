class_name HomingMissileDefinition
extends ChargeAbilityDefinition

@export_group("Missiles")
@export var missile_scene: PackedScene
@export_range(1, 32, 1) var min_missile_count: int = 2
@export_range(1, 32, 1) var max_missile_count: int = 10
@export_range(0.01, 30.0, 0.01, "suffix:s") var flight_duration: float = 4.0

@export_group("Flight")
@export_range(1.0, 5000.0, 1.0, "suffix:px/s") var speed: float = 900.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var initial_acquisition_delay: float = 0.1
@export var target_group: StringName = &"enemies"
@export_range(0.0, 1080.0, 1.0, "suffix:deg/s") var turn_speed_degrees: float = 540.0
@export_range(0.0, 180.0, 1.0, "suffix:deg") var wobble_degrees: float = 18.0
@export_range(0.0, 20.0, 0.1, "suffix:Hz") var wobble_frequency: float = 2.5
@export_range(0.0, 500.0, 1.0, "suffix:px") var departure_distance: float = 30.0

@export_group("Hit")
@export_range(0.0, 1000.0, 0.1) var damage: float = 5.0
@export_range(-5000.0, 5000.0, 10.0, "suffix:px/s") var impulse_strength: float = 300.0

@export_group("Audio")
@export var activation_cue: SoundCue
@export var hit_cue: SoundCue


func get_missile_count(charge_level: float) -> int:
	var level := clampf(charge_level, 0.0, 1.0)
	return roundi(lerpf(min_missile_count, max_missile_count, level))
