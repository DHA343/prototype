class_name Trail
extends Line2D

enum SourcePositionMode {
	SOURCE_POSITION,
	INTERPOLATED_POSITION,
}

@export var source_position_mode: SourcePositionMode = SourcePositionMode.SOURCE_POSITION
@export_range(1, 500, 1) var max_points: int = 200
@export_range(0.0, 32.0, 0.1, "suffix:px") var min_distance: float = 4.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var point_lifetime: float = 0.5

var _source: Node2D
var _get_interpolated_position: Callable
var _point_ages: Array[float] = []

var _is_lifetime_transitioning: bool = false
var _lifetime_transition_start: float = 0.0
var _lifetime_transition_target: float = 0.0
var _lifetime_transition_duration: float = 0.0
var _lifetime_transition_elapsed: float = 0.0


func _ready() -> void:
	clear_trail()


func _process(delta: float) -> void:
	_update_lifetime_transition(delta)
	_update_point_ages(delta)

	if point_lifetime <= 0.0:
		return

	if _source == null:
		return

	var local_point_position := to_local(_get_source_global_position())
	var point_count := get_point_count()

	if point_count > 0:
		var last_point_position := get_point_position(point_count - 1)

		if local_point_position.distance_to(last_point_position) < min_distance:
			return

	add_point(local_point_position)
	_point_ages.append(0.0)

	while get_point_count() > max_points:
		_remove_oldest_point()


func setup(source: Node2D, get_interpolated_position: Callable = Callable()) -> void:
	assert(source != null, "source must not be null.")

	_source = source
	_get_interpolated_position = get_interpolated_position

	_validate_interpolated_position_getter()


func clear_trail() -> void:
	clear_points()
	_point_ages.clear()


func set_point_lifetime(value: float) -> void:
	if value < 0.0:
		push_warning("Trail point_lifetime was clamped to 0.0.")

	point_lifetime = maxf(value, 0.0)
	_is_lifetime_transitioning = false


func transition_point_lifetime(value: float, duration: float) -> void:
	if value < 0.0:
		push_warning("Trail point_lifetime transition target was clamped to 0.0.")

	var target_lifetime := maxf(value, 0.0)

	if duration <= 0.0:
		set_point_lifetime(target_lifetime)
		return

	_is_lifetime_transitioning = true
	_lifetime_transition_start = point_lifetime
	_lifetime_transition_target = target_lifetime
	_lifetime_transition_duration = duration
	_lifetime_transition_elapsed = 0.0


func _validate_interpolated_position_getter() -> void:
	if source_position_mode != SourcePositionMode.INTERPOLATED_POSITION:
		return

	assert(
		_get_interpolated_position.is_valid(),
		"get_interpolated_position must be valid when source_position_mode is INTERPOLATED_POSITION."
	)

	if not _get_interpolated_position.is_valid():
		push_error("get_interpolated_position must be valid when source_position_mode is INTERPOLATED_POSITION.")


func _get_source_global_position() -> Vector2:
	match source_position_mode:
		SourcePositionMode.SOURCE_POSITION:
			return _source.global_position

		SourcePositionMode.INTERPOLATED_POSITION:
			if _get_interpolated_position.is_valid():
				var interpolated_position: Vector2 = _get_interpolated_position.call()
				return interpolated_position

			return _source.global_position

		_:
			return _source.global_position


func _update_lifetime_transition(delta: float) -> void:
	if not _is_lifetime_transitioning:
		return

	_lifetime_transition_elapsed += delta

	var progress := _lifetime_transition_elapsed / _lifetime_transition_duration
	progress = clampf(progress, 0.0, 1.0)

	point_lifetime = lerpf(_lifetime_transition_start, _lifetime_transition_target, progress)

	if progress >= 1.0:
		point_lifetime = _lifetime_transition_target
		_is_lifetime_transitioning = false


func _update_point_ages(delta: float) -> void:
	for i in range(_point_ages.size()):
		_point_ages[i] += delta

	while _point_ages.size() > 0 and _point_ages[0] >= point_lifetime:
		_remove_oldest_point()


func _remove_oldest_point() -> void:
	assert(get_point_count() > 0, "Cannot remove point because Trail has no points.")
	assert(_point_ages.size() > 0, "Cannot remove point age because Trail has no point ages.")

	remove_point(0)
	_point_ages.remove_at(0)
