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


static func play(
	p_cue: OneShotCameraShakeCue,
	p_impact_direction: Vector2 = Vector2.ZERO,
	p_strength_scale: float = 1.0
) -> CameraShakeRequest:
	assert(p_cue != null, "A one-shot cue is required.")
	var request := CameraShakeRequest.new()
	request.cue = p_cue
	request.operation = Operation.PLAY
	request.impact_direction = p_impact_direction
	request.strength_scale = p_strength_scale
	return request


static func start(
	p_cue: SustainCameraShakeCue,
	p_source: Object,
	p_strength_scale: float = 1.0
) -> CameraShakeRequest:
	assert(p_cue != null, "A sustain cue is required.")
	assert(p_source != null, "A sustain source is required.")
	var request := CameraShakeRequest.new()
	request.cue = p_cue
	request.operation = Operation.START
	request.source_id = p_source.get_instance_id()
	request.source_reference = weakref(p_source)
	request.strength_scale = p_strength_scale
	return request


static func update(p_source: Object, p_strength_scale: float) -> CameraShakeRequest:
	assert(p_source != null, "A sustain source is required.")
	var request := CameraShakeRequest.new()
	request.operation = Operation.UPDATE
	request.source_id = p_source.get_instance_id()
	request.strength_scale = p_strength_scale
	return request


static func stop(p_source: Object) -> CameraShakeRequest:
	assert(p_source != null, "A sustain source is required.")
	var request := CameraShakeRequest.new()
	request.operation = Operation.STOP
	request.source_id = p_source.get_instance_id()
	return request
