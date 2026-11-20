class_name SoundRequest
extends RefCounted

var cue: SoundCue
var world_position: Vector2
var source_id: int


func _init(p_cue: SoundCue, p_world_position: Vector2, p_source: Object) -> void:
	assert(p_source != null, "p_source must not be null.")

	cue = p_cue
	world_position = p_world_position
	source_id = p_source.get_instance_id()
