class_name CameraShakeCue
extends Resource

enum Lifetime {
	ONE_SHOT,
	SUSTAIN,
}

enum KickDirectionMode {
	NONE,
	OPPOSITE_IMPACT,
}

@export var lifetime: Lifetime = Lifetime.ONE_SHOT
@export_range(0.0, 1.0, 0.01) var strength: float = 1.0
@export_range(0.0, 5.0, 0.01, "suffix:s") var duration: float = 0.1
@export_range(0.0, 5.0, 0.01, "suffix:s") var release_duration: float = 0.1
@export_range(0.0, 10.0, 0.01) var kick_weight: float = 1.0
@export_range(0.0, 10.0, 0.01) var low_noise_weight: float = 0.0
@export_range(0.0, 10.0, 0.01) var high_noise_weight: float = 0.0
@export var kick_direction_mode: KickDirectionMode = KickDirectionMode.NONE
