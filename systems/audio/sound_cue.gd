@tool
class_name SoundCue
extends Resource

enum AggregationScope {
	PER_SOURCE,
	PER_CUE,
}

@export_group("Audio")
@export var stream: AudioStream
@export var bus: StringName = &"SFX"
@export_range(-40.0, 24.0, 0.1, "suffix:dB") var volume_db: float = 0.0

@export_group("Pitch")
@export_range(-24.0, 24.0, 0.1, "suffix:semitones") var pitch_semitones: float = 0.0
@export_range(0.0, 12.0, 0.1, "suffix:semitones") var random_pitch_semitones: float = 0.0

@export_group("Aggregation")
@export var aggregation_scope: AggregationScope = AggregationScope.PER_SOURCE
@export_range(0.0, 0.2, 0.005, "suffix:s") var aggregation_window: float = 0.0

@export_group("Voice Limit")
@export_range(0, 64, 1) var max_instances: int = 0


func _init() -> void:
	if not Engine.is_editor_hint():
		return

	if not AudioServer.bus_layout_changed.is_connected(_on_audio_bus_changed):
		AudioServer.bus_layout_changed.connect(_on_audio_bus_changed)
	if not AudioServer.bus_renamed.is_connected(_on_audio_bus_renamed):
		AudioServer.bus_renamed.connect(_on_audio_bus_renamed)


func roll_pitch_scale() -> float:
	var total_semitones := pitch_semitones
	if random_pitch_semitones > 0.0:
		total_semitones += randf_range(-random_pitch_semitones, random_pitch_semitones)

	return pow(2.0, total_semitones / 12.0)


func _validate_property(property: Dictionary) -> void:
	if property.name != &"bus":
		return

	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = _get_audio_bus_hint()


func _get_audio_bus_hint() -> String:
	var bus_names: PackedStringArray = []
	for bus_index in AudioServer.get_bus_count():
		bus_names.append(AudioServer.get_bus_name(bus_index))

	return ",".join(bus_names)


func _on_audio_bus_changed() -> void:
	notify_property_list_changed()


func _on_audio_bus_renamed(
	_bus_index: int,
	_old_name: StringName,
	_new_name: StringName
) -> void:
	notify_property_list_changed()
