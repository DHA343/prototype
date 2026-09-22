class_name CameraShakeCue
extends Resource

enum Lifetime {
	ONE_SHOT,
	SUSTAIN,
}

enum KickDirection {
	WITH_IMPACT,
	OPPOSITE_IMPACT,
}

@export_group("General")
@export var lifetime: Lifetime = Lifetime.ONE_SHOT
@export_range(0.0, 1.0, 0.01) var base_strength: float = 0.5

@export_group("One Shot")
@export_range(0.0, 1.0, 0.01, "suffix:s") var one_shot_duration: float = 0.0

@export_group("Sustain")
@export_range(0.0, 1.0, 0.01, "suffix:s") var sustain_release_duration: float = 0.0

@export_group("Composition")
@export_range(0.0, 10.0, 0.1) var kick_weight: float = 0.0
@export_range(0.0, 10.0, 0.1) var low_noise_weight: float = 0.0
@export_range(0.0, 10.0, 0.1) var high_noise_weight: float = 0.0
@export var kick_direction: KickDirection = KickDirection.WITH_IMPACT
