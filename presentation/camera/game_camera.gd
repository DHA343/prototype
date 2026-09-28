class_name GameCamera
extends Camera2D

@export var base_offset: Vector2 = Vector2.ZERO
@export_group("Follow")
## Camera shift when the predicted orb reaches the viewport edge.
@export_range(0.0, 100.0, 1.0, "suffix:px") var max_offset_x: float = 60.0
@export_range(0.0, 100.0, 1.0, "suffix:px") var max_offset_y: float = 35.0
@export_range(0.0, 0.15, 0.01, "suffix:s") var prediction_time: float = 0.07
@export_range(0.01, 0.5, 0.01, "suffix:s") var response_time: float = 0.3

var _follow_target: Orb
var _follow_offset: Vector2 = Vector2.ZERO

@onready var _shake: CameraShake = $CameraShake


func _ready() -> void:
	offset = base_offset


func _process(delta: float) -> void:
	var desired_offset := Vector2.ZERO
	if _follow_target != null:
		var predicted_position := _follow_target.get_interpolated_visual_position() \
			+ _follow_target.movement.velocity * prediction_time
		var relative_position := predicted_position - global_position - base_offset - _follow_offset
		var half_view_size := get_viewport_rect().size * 0.5
		desired_offset = Vector2(
			clampf(relative_position.x / maxf(half_view_size.x, 1.0), -1.0, 1.0) * max_offset_x,
			clampf(relative_position.y / maxf(half_view_size.y, 1.0), -1.0, 1.0) * max_offset_y
		)

	var blend := 1.0 - exp(-delta / response_time)
	_follow_offset = _follow_offset.lerp(desired_offset, blend)

	offset = base_offset + _follow_offset + _shake.update(delta)


func setup_follow(target: Orb) -> void:
	assert(target != null, "follow target must not be null.")
	_follow_target = target
