@tool
class_name PinballBoundary
extends Node2D

signal geometry_changed

const SURFACE_COLOR: Color = Color(0.48, 0.52, 0.56)
const COMPUTED_PROPERTIES: Array[String] = [
	"left_connection_y", "right_connection_y", "left_lower_length", "right_lower_length",
	"left_flipper_length", "right_flipper_length", "upper_radius_limit", "lower_radius_limit",
]

@export_group("Playfield")
## This node's origin is the center of the upper wall.
@export_range(600.0, 1920.0, 3.0, "suffix:px") var width: float = 1392.0:
	set(value):
		width = value
		_schedule_rebuild()
## Distance from the upper wall to the lower reference edge, not to the opening.
@export_range(360.0, 1920.0, 3.0, "suffix:px") var height: float = 1080.0:
	set(value):
		height = value
		_schedule_rebuild()

@export_group("Lower")
@export_range(48.0, 960.0, 3.0, "suffix:px") var opening_width: float = 288.0:
	set(value):
		opening_width = value
		_schedule_rebuild()
## X offsets from center. Y is the upward distance from the lower reference edge.
@export var opening_offset: Vector2 = Vector2(0.0, 162.0):
	set(value):
		opening_offset = value
		_schedule_rebuild()
## Measured from horizontal, descending toward the opening.
@export_range(0.0, 60.0, 0.5, "suffix:deg") var lower_angle: float = 18.6:
	set(value):
		lower_angle = value
		_schedule_rebuild()

@export_group("Corners")
@export_range(0.0, 192.0, 3.0, "suffix:px") var upper_corner_radius: float = 72.0:
	set(value):
		upper_corner_radius = value
		_schedule_rebuild()
@export_range(0.0, 192.0, 3.0, "suffix:px") var lower_corner_radius: float = 72.0:
	set(value):
		lower_corner_radius = value
		_schedule_rebuild()

@export_group("Flipper Interval")
## Distance from the side/lower intersection along the lower straight line.
@export_range(0.0, 1200.0, 3.0, "suffix:px") var start_distance: float = 330.0:
	set(value):
		start_distance = value
		_schedule_rebuild()
## Inactive straight length next to the opening. Zero reaches the opening edge.
@export_range(0.0, 480.0, 3.0, "suffix:px") var opening_margin: float = 0.0:
	set(value):
		opening_margin = value
		_schedule_rebuild()

@export_group("Restitution")
## Upper wall, side walls and upper rounded corners.
@export_range(0.0, 1.0, 0.01) var wall_restitution: float = 0.9
## Lower rounded corners and lower connecting walls.
@export_range(0.0, 1.0, 0.01) var lower_restitution: float = 0.1

@export_group("Computed")
## Side/lower intersection Y, measured from the upper wall; before corner rounding.
@export var left_connection_y: float:
	get:
		return connection_position(0).y
@export var right_connection_y: float:
	get:
		return connection_position(1).y
@export var left_lower_length: float:
	get:
		return lower_length(0)
@export var right_lower_length: float:
	get:
		return lower_length(1)
## Zero means this interval is disabled because it does not fit.
@export var left_flipper_length: float:
	get:
		return _flipper_length(0)
@export var right_flipper_length: float:
	get:
		return _flipper_length(1)
@export var upper_radius_limit: float:
	get:
		var height := minf(left_connection_y, right_connection_y)
		return maxf(0.0, minf(width, height) * 0.45)
@export var lower_radius_limit: float:
	get:
		var available := minf(minf(left_connection_y, right_connection_y),
			minf(left_lower_length, right_lower_length)) * 0.45
		return maxf(0.0, available / tan(_lower_turn() * 0.5))

var bottom: float:
	get:
		return opening_center.y
var opening_center: Vector2:
	get:
		return Vector2(opening_offset.x, height - opening_offset.y)

var _walls: StaticBody2D
var _lower: StaticBody2D
var _wall_shape: ConcavePolygonShape2D
var _lower_shape: ConcavePolygonShape2D
var _outline: PackedVector2Array = PackedVector2Array()
var _static_segments: PackedVector2Array = PackedVector2Array()
var _rebuild_pending: bool = false

@onready var _sockets: Array[PinballSocket] = [
	$LeftPivot, $LeftTip, $RightPivot, $RightTip,
]


func _ready() -> void:
	_walls = _create_surface("Walls")
	_wall_shape = (_walls.get_child(0) as CollisionShape2D).shape as ConcavePolygonShape2D
	_lower = _create_surface("Lower")
	_lower_shape = (_lower.get_child(0) as CollisionShape2D).shape as ConcavePolygonShape2D
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	if property.name in COMPUTED_PROPERTIES:
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


func _draw() -> void:
	if not _static_segments.is_empty():
		draw_multiline(_static_segments, SURFACE_COLOR, 3.0)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if not _is_layout_valid():
		warnings.append("Keep the opening inside the side walls and both lower connections below the upper wall.")
		return warnings
	if upper_corner_radius > upper_radius_limit:
		warnings.append("Upper Corner Radius is limited to %.1f px by the available wall lengths." % upper_radius_limit)
	if lower_corner_radius > lower_radius_limit:
		warnings.append("Lower Corner Radius is limited to %.1f px by the available wall lengths." % lower_radius_limit)
	for side: int in 2:
		if not _is_interval_valid(side):
			var hand := "Left" if side == 0 else "Right"
			warnings.append("%s flipper disabled: Start Distance must be >= %.1f px and < %.1f px."
				% [hand, _lower_trim(), lower_length(side) - opening_margin])
	return warnings


func restitution_for(collider: Object) -> float:
	return lower_restitution if collider == _lower else wall_restitution


func connection_position(side: int) -> Vector2:
	var x := -width * 0.5 if side == 0 else width * 0.5
	var run := absf(opening_edge(side).x - x)
	return Vector2(x, opening_center.y - run * tan(deg_to_rad(lower_angle)))


func opening_edge(side: int) -> Vector2:
	var offset := -opening_width * 0.5 if side == 0 else opening_width * 0.5
	return opening_center + Vector2(offset, 0.0)


func lower_length(side: int) -> float:
	return connection_position(side).distance_to(opening_edge(side))


func sample_interval(ratio: float, side: int) -> Vector2:
	var interval := _interval(side)
	var start := connection_position(side)
	var direction := (opening_edge(side) - start).normalized()
	return start + direction * lerpf(interval.x, interval.y, ratio)


## Static resting perimeter plus an exit corridor; moving flippers are handled by physics.
func traversable_outline() -> PackedVector2Array:
	if not _is_layout_valid():
		return PackedVector2Array()
	var result := PackedVector2Array()
	for point: Vector2 in _outline:
		result.append(to_global(point))
	result.append(to_global(opening_edge(1) + Vector2.DOWN * 192.0))
	result.append(to_global(opening_edge(0) + Vector2.DOWN * 192.0))
	return result


func exit_target() -> Vector2:
	return to_global(opening_center + Vector2.DOWN * 96.0)


func has_exited(point: Vector2, radius: float) -> bool:
	var local := to_local(point)
	return local.y > opening_center.y + radius \
		and absf(local.x - opening_center.x) <= opening_width * 0.5 - radius + 0.3


func _interval(side: int) -> Vector2:
	return Vector2(start_distance, lower_length(side) - opening_margin)


func _flipper_length(side: int) -> float:
	var interval := _interval(side)
	return interval.y - interval.x if _is_interval_valid(side) else 0.0


func _lower_turn() -> float:
	return PI * 0.5 - deg_to_rad(lower_angle)


func _lower_trim() -> float:
	return minf(lower_corner_radius, lower_radius_limit) * tan(_lower_turn() * 0.5)


func _is_layout_valid() -> bool:
	return height > 0.0 and opening_width > 0.0 \
		and absf(opening_offset.x) + opening_width * 0.5 < width * 0.5 \
		and lower_angle >= 0.0 and lower_angle <= 60.0 \
		and left_connection_y > 0.0 and right_connection_y > 0.0


func _is_interval_valid(side: int) -> bool:
	if not _is_layout_valid():
		return false
	var interval := _interval(side)
	return opening_margin >= 0.0 and interval.x >= _lower_trim() and interval.y > interval.x


func _schedule_rebuild() -> void:
	if is_node_ready() and not _rebuild_pending:
		_rebuild_pending = true
		_rebuild.call_deferred()


func _create_surface(surface_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = surface_name
	body.collision_layer = 2
	body.collision_mask = 5
	add_child(body, false, Node.INTERNAL_MODE_BACK)
	var collision := CollisionShape2D.new()
	collision.shape = ConcavePolygonShape2D.new()
	body.add_child(collision)
	return body


func _rebuild() -> void:
	_rebuild_pending = false
	_outline.clear()
	_static_segments.clear()
	var wall_segments := PackedVector2Array()
	var lower_segments := PackedVector2Array()
	for side: int in 2:
		var valid := _is_interval_valid(side)
		var pivot := _sockets[side * 2]
		var tip := _sockets[side * 2 + 1]
		pivot.position = sample_interval(0.0, side)
		tip.position = sample_interval(1.0, side)
		pivot.rotation = (tip.position - pivot.position).angle()
		tip.rotation = pivot.rotation
		pivot.available = valid
		tip.available = valid
	if _is_layout_valid():
		var vertices := PackedVector2Array([
			opening_edge(0), connection_position(0), Vector2(-width * 0.5, 0.0),
			Vector2(width * 0.5, 0.0), connection_position(1), opening_edge(1),
		])
		var upper_radius := minf(upper_corner_radius, upper_radius_limit)
		var lower_radius := minf(lower_corner_radius, lower_radius_limit)
		var left_lower_end := 0
		var right_lower_start := 0
		_outline.append(vertices[0])
		for index in range(1, vertices.size() - 1):
			if index == 4:
				right_lower_start = _outline.size()
			var radius := lower_radius if index == 1 or index == 4 else upper_radius
			_append_corner(vertices[index - 1], vertices[index], vertices[index + 1], radius)
			if index == 1:
				left_lower_end = _outline.size() - 1
		_outline.append(vertices[vertices.size() - 1])
		for index in _outline.size() - 1:
			var start := _outline[index]
			var end := _outline[index + 1]
			# Leave the rotating interval empty; no invisible resting wall remains beneath it.
			if index == 0 and _is_interval_valid(0):
				_append_segment(lower_segments, start, sample_interval(1.0, 0))
				_append_segment(lower_segments, sample_interval(0.0, 0), end)
			elif index == _outline.size() - 2 and _is_interval_valid(1):
				_append_segment(lower_segments, start, sample_interval(0.0, 1))
				_append_segment(lower_segments, sample_interval(1.0, 1), end)
			elif index < left_lower_end or index >= right_lower_start:
				_append_segment(lower_segments, start, end)
			else:
				_append_segment(wall_segments, start, end)
	_wall_shape.segments = wall_segments
	_lower_shape.segments = lower_segments
	_static_segments.append_array(wall_segments)
	_static_segments.append_array(lower_segments)
	queue_redraw()
	update_configuration_warnings()
	geometry_changed.emit()


func _append_segment(segments: PackedVector2Array, start: Vector2, end: Vector2) -> void:
	if not start.is_equal_approx(end):
		segments.append(start)
		segments.append(end)


func _append_corner(previous: Vector2, point: Vector2, next: Vector2, radius: float) -> void:
	var incoming := (point - previous).normalized()
	var outgoing := (next - point).normalized()
	var turn := acos(clampf(incoming.dot(outgoing), -1.0, 1.0))
	var bend := incoming.cross(outgoing)
	if radius <= 0.0 or absf(bend) < 0.0001:
		_outline.append(point)
		return
	var trim := radius * tan(turn * 0.5)
	var start := point - incoming * trim
	var center := start + Vector2(-incoming.y, incoming.x) * signf(bend) * radius
	var radial := start - center
	var steps := maxi(2, ceili(turn * radius / 6.0))
	for index in steps + 1:
		var angle := turn * signf(bend) * float(index) / steps
		_outline.append(center + radial.rotated(angle))
