class_name WorldSoundOutput
extends Node2D

signal sound_dropped(cue: SoundCue, reason: DropReason)

enum DropReason {
	CUE_LIMIT,
	GLOBAL_LIMIT,
}

@export_range(1, 64, 1) var initial_pool_size: int = 16
@export_range(1, 64, 1) var max_voices: int = 64

var _players: Array[AudioStreamPlayer2D] = []
var _available_players: Array[AudioStreamPlayer2D] = []
var _pending_aggregations: Dictionary[StringName, PendingAggregation] = {}
var _cue_active_counts: Dictionary[int, int] = {}
## This map is the source of truth for active voices and their owning cues.
var _player_cues: Dictionary[AudioStreamPlayer2D, SoundCue] = {}
var _cue_limit_drop_count: int = 0
var _global_limit_drop_count: int = 0


func _ready() -> void:
	max_voices = maxi(max_voices, 1)
	initial_pool_size = clampi(initial_pool_size, 1, max_voices)

	for _index in initial_pool_size:
		_create_player()


func _process(_delta: float) -> void:
	_flush_expired_aggregations()


## True means queued for aggregation, not guaranteed playback; limits apply when flushed.
func request(sound_request: SoundRequest) -> bool:
	if sound_request == null:
		return false

	var cue := sound_request.cue
	if cue == null:
		return false
	if cue.stream == null:
		return false
	if AudioServer.get_bus_index(cue.bus) < 0:
		push_error("SoundCue references an unknown audio bus: %s" % cue.bus)
		return false

	var aggregation_key := _get_aggregation_key(cue, sound_request.source_id)
	var current_frame := Engine.get_process_frames()
	var current_time_usec := Time.get_ticks_usec()
	var pending: PendingAggregation = _pending_aggregations.get(aggregation_key)
	if pending != null and _should_flush_pending(pending, current_frame, current_time_usec):
		_flush_pending_aggregation(aggregation_key)
		pending = null

	if pending == null:
		pending = PendingAggregation.new(
			cue,
			sound_request.world_position,
			current_frame,
			current_time_usec,
			maxf(cue.aggregation_window, 0.0)
		)
		_pending_aggregations[aggregation_key] = pending
	else:
		pending.add_request(sound_request.world_position)

	return true


func get_active_voice_count() -> int:
	return _player_cues.size()


func get_allocated_voice_count() -> int:
	return _players.size()


func get_pending_aggregation_count() -> int:
	return _pending_aggregations.size()


func get_cue_limit_drop_count() -> int:
	return _cue_limit_drop_count


func get_global_limit_drop_count() -> int:
	return _global_limit_drop_count


func _flush_expired_aggregations() -> void:
	if _pending_aggregations.is_empty():
		return

	var current_frame := Engine.get_process_frames()
	var current_time_usec := Time.get_ticks_usec()
	var keys_to_flush: Array[StringName] = []
	for aggregation_key in _pending_aggregations:
		var pending: PendingAggregation = _pending_aggregations[aggregation_key]
		if _should_flush_pending(pending, current_frame, current_time_usec):
			keys_to_flush.append(aggregation_key)

	for aggregation_key in keys_to_flush:
		_flush_pending_aggregation(aggregation_key)


func _should_flush_pending(
	pending: PendingAggregation,
	current_frame: int,
	current_time_usec: int
) -> bool:
	if pending.aggregation_window <= 0.0:
		# A zero window still combines requests within one process frame.
		return pending.first_frame < current_frame

	var elapsed_usec := current_time_usec - pending.first_request_usec
	return elapsed_usec >= int(pending.aggregation_window * 1_000_000.0)


func _flush_pending_aggregation(aggregation_key: StringName) -> void:
	var pending: PendingAggregation = _pending_aggregations.get(aggregation_key)
	if pending == null:
		return

	_pending_aggregations.erase(aggregation_key)
	_play_aggregated(pending)


func _play_aggregated(pending: PendingAggregation) -> void:
	var cue := pending.cue
	var active_cue_count := _get_cue_active_count(cue)
	if cue.max_instances > 0 and active_cue_count >= cue.max_instances:
		_register_drop(cue, DropReason.CUE_LIMIT)
		return

	if _player_cues.size() >= max_voices:
		_register_drop(cue, DropReason.GLOBAL_LIMIT)
		return

	var player := _acquire_player()
	if player == null:
		push_error("WorldSoundOutput could not acquire a voice from its pool.")
		return

	player.stream = cue.stream
	player.volume_db = cue.volume_db
	player.pitch_scale = cue.roll_pitch_scale()
	player.bus = cue.bus
	player.global_position = pending.get_average_position()

	_player_cues[player] = cue
	_set_cue_active_count(cue, active_cue_count + 1)
	player.play()


func _acquire_player() -> AudioStreamPlayer2D:
	if not _available_players.is_empty():
		return _available_players.pop_back()

	if _players.size() >= max_voices:
		return null

	_create_player()
	return _available_players.pop_back()


func _create_player() -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.max_polyphony = 1
	player.finished.connect(_on_player_finished.bind(player))
	add_child(player)

	_players.append(player)
	_available_players.append(player)
	return player


func _on_player_finished(player: AudioStreamPlayer2D) -> void:
	if not _player_cues.has(player):
		return

	var cue: SoundCue = _player_cues[player]
	_player_cues.erase(player)
	_set_cue_active_count(cue, _get_cue_active_count(cue) - 1)

	player.stream = null
	if not _available_players.has(player):
		_available_players.append(player)


func _get_aggregation_key(cue: SoundCue, source_id: int) -> StringName:
	var cue_id := cue.get_instance_id()
	if cue.aggregation_scope == SoundCue.AggregationScope.PER_CUE:
		return StringName("cue:%s" % cue_id)

	return StringName("source:%s:%s" % [cue_id, source_id])


func _get_cue_active_count(cue: SoundCue) -> int:
	return int(_cue_active_counts.get(cue.get_instance_id(), 0))


func _set_cue_active_count(cue: SoundCue, count: int) -> void:
	var cue_id := cue.get_instance_id()
	if count <= 0:
		_cue_active_counts.erase(cue_id)
		return

	_cue_active_counts[cue_id] = count


func _register_drop(cue: SoundCue, reason: DropReason) -> void:
	match reason:
		DropReason.CUE_LIMIT:
			_cue_limit_drop_count += 1
		DropReason.GLOBAL_LIMIT:
			_global_limit_drop_count += 1

	sound_dropped.emit(cue, reason)


class PendingAggregation:
	var cue: SoundCue
	var world_position_sum: Vector2
	var request_count: int = 1
	var first_frame: int
	var first_request_usec: int
	var aggregation_window: float


	func _init(
		p_cue: SoundCue,
		p_world_position: Vector2,
		p_first_frame: int,
		p_first_request_usec: int,
		p_aggregation_window: float
	) -> void:
		cue = p_cue
		world_position_sum = p_world_position
		first_frame = p_first_frame
		first_request_usec = p_first_request_usec
		aggregation_window = p_aggregation_window


	func add_request(p_world_position: Vector2) -> void:
		world_position_sum += p_world_position
		request_count += 1


	func get_average_position() -> Vector2:
		return world_position_sum / float(request_count)
