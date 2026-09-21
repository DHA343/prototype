class_name CameraShakeRequest
extends RefCounted

enum Operation {
	PLAY,
	START,
	UPDATE,
	STOP,
}

var cue: CameraShakeCue
var operation: Operation = Operation.PLAY
var source_id: int = 0
var source_reference: WeakRef
var impact_direction: Vector2 = Vector2.ZERO
var strength_scale: float = 1.0
