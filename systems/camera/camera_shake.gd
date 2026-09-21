class_name CameraShake
extends Node

@export var max_offset: Vector2 = Vector2(16.0, 9.0)
@export_range(0.0, 1.0, 0.01) var master_intensity: float = 1.0
@export_range(0.0, 100.0, 1.0) var low_noise_speed: float = 8.0
@export_range(0.0, 100.0, 1.0) var high_noise_speed: float = 36.0

var _one_shots: Array[OneShotState] = []
var _sustains: Dictionary[int, SustainState] = {}
var _low_noise_position: float = 0.0
var _high_noise_position: float = 0.0
var _low_noise: FastNoiseLite
var _high_noise: FastNoiseLite
var _camera: Camera2D


func _ready() -> void:
	_camera = get_parent() as Camera2D
	assert(_camera != null, "CameraShake must be a child of Camera2D.")

	_low_noise = _create_noise()
	_high_noise = _create_noise()
	_camera.offset = Vector2.ZERO
	set_process(false)


func _exit_tree() -> void:
	if _camera != null:
		_camera.offset = Vector2.ZERO


func _process(delta: float) -> void:
	_release_destroyed_sources()
	_camera.offset = _calculate_offset() * master_intensity
	_advance_states(delta)
	_low_noise_position += low_noise_speed * delta
	_high_noise_position += high_noise_speed * delta

	if _one_shots.is_empty() and _sustains.is_empty():
		_camera.offset = Vector2.ZERO
		set_process(false)


func request(request: CameraShakeRequest) -> void:
	match request.operation:
		CameraShakeRequest.Operation.PLAY:
			_request_one_shot(request)
		CameraShakeRequest.Operation.START:
			_start_sustain(request)
		CameraShakeRequest.Operation.UPDATE:
			_update_sustain(request)
		CameraShakeRequest.Operation.STOP:
			_stop_sustain(request.source_id)

	if not _one_shots.is_empty() or not _sustains.is_empty():
		set_process(true)


func _request_one_shot(request: CameraShakeRequest) -> void:
	assert(request.cue != null, "A cue is required for PLAY.")
	assert(request.cue.lifetime == CameraShakeCue.Lifetime.ONE_SHOT, "PLAY requires a one-shot cue.")
	if request.cue.duration <= 0.0:
		return

	var state := OneShotState.new()
	state.cue = request.cue
	state.impact_direction = request.impact_direction
	state.strength_scale = request.strength_scale
	_one_shots.append(state)


func _start_sustain(request: CameraShakeRequest) -> void:
	assert(request.cue != null, "A cue is required for START.")
	assert(request.cue.lifetime == CameraShakeCue.Lifetime.SUSTAIN, "START requires a sustain cue.")
	assert(request.source_id != 0, "A sustain source_id is required.")
	assert(request.source_reference != null, "A sustain source_reference is required.")

	var state := _sustains.get(request.source_id) as SustainState
	if state == null:
		state = SustainState.new()
		_sustains[request.source_id] = state
	state.cue = request.cue
	state.source_reference = request.source_reference
	state.impact_direction = request.impact_direction
	state.strength_scale = request.strength_scale
	state.is_releasing = false
	state.release_elapsed = 0.0


func _update_sustain(request: CameraShakeRequest) -> void:
	assert(request.source_id != 0, "A sustain source_id is required.")
	var state := _sustains.get(request.source_id) as SustainState
	assert(state != null, "UPDATE requires an active sustain.")
	if state == null:
		return

	state.impact_direction = request.impact_direction
	state.strength_scale = request.strength_scale


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
	state.is_releasing = true
	state.release_strength = _get_sustain_strength(state)
	state.release_elapsed = 0.0


func _calculate_offset() -> Vector2:
	var totals := ChannelStrengths.new()

	for state: OneShotState in _one_shots:
		_add_contribution(
			state.cue,
			_get_one_shot_strength(state),
			state.impact_direction,
			totals
		)
	for state: SustainState in _sustains.values():
		_add_contribution(
			state.cue,
			_get_sustain_strength(state),
			state.impact_direction,
			totals
		)

	var low_offset := _get_noise_vector(_low_noise, _low_noise_position) * totals.low_strength
	var high_offset := _get_noise_vector(_high_noise, _high_noise_position) * totals.high_strength
	var normalized_offset := totals.kick_offset + low_offset + high_offset
	if normalized_offset.length() > 1.0:
		normalized_offset = normalized_offset.normalized()
	return normalized_offset * max_offset


func _add_contribution(
	cue: CameraShakeCue,
	strength: float,
	impact_direction: Vector2,
	totals: ChannelStrengths
) -> void:
	var weight_total := cue.kick_weight + cue.low_noise_weight + cue.high_noise_weight
	if weight_total <= 0.0:
		return

	var kick_weight := cue.kick_weight / weight_total
	var low_weight := cue.low_noise_weight / weight_total
	var high_weight := cue.high_noise_weight / weight_total
	var contribution := strength * kick_weight
	if cue.kick_direction_mode == CameraShakeCue.KickDirectionMode.OPPOSITE_IMPACT \
		and not impact_direction.is_zero_approx() and contribution > totals.kick_strength:
		totals.kick_strength = contribution
		totals.kick_offset = -impact_direction.normalized() * contribution

	totals.low_strength = _saturated_add(totals.low_strength, strength * low_weight)
	totals.high_strength = _saturated_add(totals.high_strength, strength * high_weight)


func _get_one_shot_strength(state: OneShotState) -> float:
	var progress := clampf(state.elapsed / state.cue.duration, 0.0, 1.0)
	return _get_effective_strength(state.cue, state.strength_scale) * pow(1.0 - progress, 2.0)


func _get_sustain_strength(state: SustainState) -> float:
	if not state.is_releasing:
		return _get_effective_strength(state.cue, state.strength_scale)
	if state.cue.release_duration <= 0.0:
		return 0.0

	var progress := clampf(state.release_elapsed / state.cue.release_duration, 0.0, 1.0)
	return state.release_strength * pow(1.0 - progress, 2.0)


func _get_effective_strength(cue: CameraShakeCue, strength_scale: float) -> float:
	return clampf(cue.strength * maxf(strength_scale, 0.0), 0.0, 1.0)


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
	return Vector2(noise.get_noise_1d(position), noise.get_noise_1d(position + 1000.0))


func _saturated_add(first: float, second: float) -> float:
	return first + second - first * second


class OneShotState:
	var cue: CameraShakeCue
	var impact_direction: Vector2
	var strength_scale: float
	var elapsed: float = 0.0


class SustainState:
	var cue: CameraShakeCue
	var source_reference: WeakRef
	var impact_direction: Vector2
	var strength_scale: float
	var is_releasing: bool = false
	var release_strength: float = 0.0
	var release_elapsed: float = 0.0


class ChannelStrengths:
	var kick_strength: float = 0.0
	var kick_offset: Vector2 = Vector2.ZERO
	var low_strength: float = 0.0
	var high_strength: float = 0.0
