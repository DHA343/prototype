extends Node2D

const BEFORE: Color = Color(1.0, .72, .26)
const AFTER: Color = Color(.22, .95, .8)

var event: Dictionary = {}
var segments: Array[Dictionary] = []
var ghost: PackedVector2Array = []
var flippers: Array[PinballFlipper] = []
var actors: Array[Enemy] = []
var radius: float = 24.0
var show_guides: bool = true
var show_ghost: bool = true
var zoom: float = 1.0


func _draw() -> void:
	if show_ghost and ghost.size() > 1:
		draw_polyline(ghost, Color(.7, .7, .8, .3), 2.0 / zoom, true)
	if not show_guides: return
	for actor: Enemy in actors:
		if is_instance_valid(actor) and actor.active:
			draw_arc(actor.global_position, actor.radius, 0, TAU, 48,
				Color(.7, .55, 1, .8), 1.5 / zoom, true)
	for item: PinballFlipper in flippers:
		if not item.visible: continue
		var points := (item as TableFlipper).world_polygon_at(item.global_transform)
		draw_colored_polygon(points, Color(.2, .75, 1, .08))
		points.append(points[0])
		draw_polyline(points, Color(.2, .75, 1, .55), 1.5 / zoom, true)
	for segment: Dictionary in segments:
		if not segment.correction:
			draw_line(segment.start, segment.end, Color(.9, .93, 1, .28), 1.5 / zoom, true)
	if event.is_empty(): return
	var before := _vec(event.correction_start)
	var after := _vec(event.correction_end)
	draw_arc(before, radius, 0, TAU, 48, BEFORE, 2.0 / zoom, true)
	draw_arc(after, radius, 0, TAU, 48, AFTER, 2.0 / zoom, true)
	_arrow(before, after, BEFORE)
	var point := _vec(event.point)
	draw_circle(point, 4.0 / zoom, Color(1, .35, .3))
	_arrow(point, point + _vec(event.normal) * 32, Color(1, .35, .3))


func _arrow(start: Vector2, end: Vector2, color: Color) -> void:
	draw_line(start, end, color, 2.5 / zoom, true)
	if start.distance_squared_to(end) < .000001: return
	var direction := (end - start).normalized()
	var head := minf(9.0 / zoom, start.distance_to(end) * .45)
	draw_line(end, end - direction.rotated(.48) * head, color, 2.5 / zoom, true)
	draw_line(end, end - direction.rotated(-.48) * head, color, 2.5 / zoom, true)


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
