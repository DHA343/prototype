class_name CameraShake
extends Node

@export var max_shake_offset: Vector2 = Vector2(16.0, 9.0)
@export_range(0.0, 1.0, 0.01) var master_intensity: float = 1.0
@export_range(0.0, 100.0, 1.0) var low_noise_speed: float = 8.0
@export_range(0.0, 100.0, 1.0) var high_noise_speed: float = 36.0

var _one_shots: Array[OneShotState] = []
var _sustains: Dictionary[int, SustainState] = {}
var _low_noise_position: float = 0.0
var _high_noise_position: float = 0.0
var _low_noise: FastNoiseLite
var _high_noise: FastNoiseLite


func _ready() -> void:
	_low_noise = _create_noise()
	_high_noise = _create_noise()


## Called once per frame by the camera before composing its offset.
func update(delta: float) -> Vector2:
	if _one_shots.is_empty() and _sustains.is_empty():
		return Vector2.ZERO

	_release_destroyed_sources()
	var offset := _calculate_offset() * master_intensity
	_advance_states(delta)
	_low_noise_position += low_noise_speed * delta
	_high_noise_position += high_noise_speed * delta
	# Preserve this sample even if its state expires before the frame is drawn.
	return offset


func request(shake_request: CameraShakeRequest) -> void:
	match shake_request.operation:
		CameraShakeRequest.Operation.PLAY:
			_request_one_shot(shake_request)
		CameraShakeRequest.Operation.START:
			_start_sustain(shake_request)
		CameraShakeRequest.Operation.UPDATE:
			_update_sustain(shake_request)
		CameraShakeRequest.Operation.STOP:
			_stop_sustain(shake_request.source_id)


func _request_one_shot(shake_request: CameraShakeRequest) -> void:
	var cue := shake_request.cue as OneShotCameraShakeCue
	assert(cue != null, "PLAY requires OneShotCameraShakeCue.")
	if cue == null or cue.duration <= 0.0:
		return

	var state := OneShotState.new()
	state.cue = cue
	state.impact_direction = shake_request.impact_direction
	state.strength_scale = shake_request.strength_scale
	_one_shots.append(state)


func _start_sustain(shake_request: CameraShakeRequest) -> void:
	var cue := shake_request.cue as SustainCameraShakeCue
	assert(cue != null, "START requires SustainCameraShakeCue.")
	if cue == null:
		return
	assert(shake_request.source_id != 0, "A sustain source_id is required.")
	assert(shake_request.source_reference != null, "A sustain source_reference is required.")

	var state := _sustains.get(shake_request.source_id) as SustainState
	if state == null:
		state = SustainState.new()
		_sustains[shake_request.source_id] = state
	state.cue = cue
	state.source_reference = shake_request.source_reference
	state.strength_scale = shake_request.strength_scale
	state.is_releasing = false
	state.release_elapsed = 0.0


func _update_sustain(shake_request: CameraShakeRequest) -> void:
	assert(shake_request.source_id != 0, "A sustain source_id is required.")
	var state := _sustains.get(shake_request.source_id) as SustainState
	assert(state != null, "UPDATE requires an active sustain.")
	if state == null:
		return

	state.strength_scale = shake_request.strength_scale


func _stop_sustain(source_id: int) -> void:
	assert(source_id != 0, "A sustain source_id is required.")
	var state := _sustains.get(source_id) as SustainState
	assert(state != null, "STOP requires an active sustain.")
	if state != null:
		_begin_release(state)


func _release_destroyed_sources() -> void:
	for state: SustainState in _sustains.values():
		if not state.is_releasing and state.source_reference.get_ref() == null:
			_begin_release(state)


func _begin_release(state: SustainState) -> void:
	if state.is_releasing:
		return
	state.release_scale = maxf(state.strength_scale, 0.0)
	state.is_releasing = true
	state.release_elapsed = 0.0


func _calculate_offset() -> Vector2:
	var totals := ChannelStrengths.new()

	for state: OneShotState in _one_shots:
		_add_one_shot_contribution(state, totals)
	for state: SustainState in _sustains.values():
		_add_sustain_contribution(state, totals)

	var low_offset := _get_noise_vector(_low_noise, _low_noise_position) * totals.low_strength
	var high_offset := _get_noise_vector(_high_noise, _high_noise_position) * totals.high_strength
	var normalized_offset := totals.kick_offset + low_offset + high_offset
	if normalized_offset.length() > 1.0:
		normalized_offset = normalized_offset.normalized()
	return normalized_offset * max_shake_offset


func _add_one_shot_contribution(state: OneShotState, totals: ChannelStrengths) -> void:
	var scale := _get_one_shot_scale(state)
	var kick_contribution := _scaled_channel_strength(state.cue.kick_strength, scale)
	if kick_contribution > 0.0 and not state.impact_direction.is_zero_approx() \
		and kick_contribution > totals.kick_strength:
		var kick_direction := state.impact_direction.normalized()
		if state.cue.kick_direction == OneShotCameraShakeCue.KickDirection.OPPOSITE_IMPACT:
			kick_direction = -kick_direction
		totals.kick_strength = kick_contribution
		totals.kick_offset = kick_direction * kick_contribution

	var low_contribution := _scaled_channel_strength(state.cue.low_noise_strength, scale)
	var high_contribution := _scaled_channel_strength(state.cue.high_noise_strength, scale)
	totals.low_strength = _saturated_add(totals.low_strength, low_contribution)
	totals.high_strength = _saturated_add(totals.high_strength, high_contribution)


func _add_sustain_contribution(state: SustainState, totals: ChannelStrengths) -> void:
	var scale := _get_sustain_scale(state)
	var low_contribution := _scaled_channel_strength(state.cue.low_noise_strength, scale)
	var high_contribution := _scaled_channel_strength(state.cue.high_noise_strength, scale)
	totals.low_strength = _saturated_add(totals.low_strength, low_contribution)
	totals.high_strength = _saturated_add(totals.high_strength, high_contribution)


func _scaled_channel_strength(base_strength: float, scale: float) -> float:
	return clampf(base_strength * scale, 0.0, 1.0)


func _get_one_shot_scale(state: OneShotState) -> float:
	var progress := clampf(state.elapsed / state.cue.duration, 0.0, 1.0)
	return maxf(state.strength_scale, 0.0) * pow(1.0 - progress, 2.0)


func _get_sustain_scale(state: SustainState) -> float:
	if not state.is_releasing:
		return maxf(state.strength_scale, 0.0)
	if state.cue.release_duration <= 0.0:
		return 0.0

	var progress := clampf(state.release_elapsed / state.cue.release_duration, 0.0, 1.0)
	return state.release_scale * pow(1.0 - progress, 2.0)


func _advance_states(delta: float) -> void:
	for index: int in range(_one_shots.size() - 1, -1, -1):
		var state := _one_shots[index]
		state.elapsed += delta
		if state.elapsed >= state.cue.duration:
			_one_shots.remove_at(index)

	for source_id: int in _sustains.keys():
		var state: SustainState = _sustains[source_id]
		if not state.is_releasing:
			continue
		state.release_elapsed += delta
		if state.release_elapsed >= state.cue.release_duration:
			_sustains.erase(source_id)


func _create_noise() -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0
	noise.seed = randi()
	return noise


func _get_noise_vector(noise: FastNoiseLite, position: float) -> Vector2:
	var sample := Vector2(noise.get_noise_1d(position), noise.get_noise_1d(position + 1000.0))
	if sample.length_squared() > 1.0:
		return sample.normalized()
	return sample


func _saturated_add(first: float, second: float) -> float:
	return first + second - first * second


class OneShotState:
	var cue: OneShotCameraShakeCue
	var impact_direction: Vector2
	var strength_scale: float = 1.0
	var elapsed: float = 0.0


class SustainState:
	var cue: SustainCameraShakeCue
	var source_reference: WeakRef
	var strength_scale: float = 1.0
	var is_releasing: bool = false
	var release_scale: float = 0.0
	var release_elapsed: float = 0.0


class ChannelStrengths:
	var kick_strength: float = 0.0
	var kick_offset: Vector2 = Vector2.ZERO
	var low_strength: float = 0.0
	var high_strength: float = 0.0
