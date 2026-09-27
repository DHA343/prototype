class_name OneShotCameraShakeCue
extends CameraShakeCue

enum KickDirection {
	WITH_IMPACT,
	OPPOSITE_IMPACT,
}

@export_group("One Shot")
@export_range(0.0, 0.5, 0.01, "suffix:s") var duration: float = 0.0
@export_range(0.0, 1.0, 0.01) var kick_strength: float = 0.0
@export var kick_direction: KickDirection = KickDirection.WITH_IMPACT
