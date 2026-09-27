class_name BoostTrail
extends Node2D

@export_range(0.0, 1.0, 0.01, "suffix:s") var boost_point_lifetime: float = 0.12
@export_range(0.0, 2.0, 0.01, "suffix:s") var fade_in_duration: float = 0.1
@export_range(0.0, 2.0, 0.01, "suffix:s") var hold_duration: float = 0.1
@export_range(0.0, 2.0, 0.01, "suffix:s") var fade_out_duration: float = 0.2

var _remaining_duration: float = 0.0
var _is_active: bool = false

@onready var _trail: Trail = $Trail


func _process(delta: float) -> void:
	if not _is_active:
		return

	_remaining_duration -= delta
	if _remaining_duration > 0.0:
		return

	_is_active = false
	_remaining_duration = 0.0
	_trail.transition_point_lifetime(0.0, fade_out_duration)


func setup(source: Node2D, get_interpolated_position: Callable) -> void:
	assert(source != null, "source must not be null.")
	assert(get_interpolated_position.is_valid(), "get_interpolated_position must be valid.")

	_trail.setup(source, get_interpolated_position)
	_trail.set_point_lifetime(0.0)
	_trail.clear_trail()
	_remaining_duration = 0.0
	_is_active = false


func play() -> void:
	_is_active = true
	_remaining_duration = fade_in_duration + hold_duration
	_trail.transition_point_lifetime(boost_point_lifetime, fade_in_duration)


func stop_immediately() -> void:
	_is_active = false
	_remaining_duration = 0.0
	_trail.set_point_lifetime(0.0)
	_trail.clear_trail()
