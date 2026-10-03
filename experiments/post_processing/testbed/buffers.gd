extends Node2D

var testbed: Node2D
var mode: int = 0
var _previous: Dictionary[int, Vector2] = {}
var _seen: Dictionary[int, bool] = {}
var _polygons: Array[PackedVector2Array] = []
var _colors: Array[Color] = []


func reset_motion() -> void:
	_previous.clear()


func _process(_delta: float) -> void:
	_polygons.clear()
	_colors.clear()
	_seen.clear()
	if int(testbed.get("source")) == 0:
		var main: Node2D = testbed.get("_main")
		if main != null:
			if bool(testbed.get("mask_orb")):
				_add_visual(main.get_node("WorldLayer/Actors/Orb/Visual") as Node2D)
			if bool(testbed.get("mask_enemies")):
				for enemy in main.get_node("WorldLayer/Actors/Enemies").get_children():
					var visual := enemy.get_node_or_null("VisualRoot/Visual") as Node2D
					if visual != null:
						_add_visual(visual)
	else:
		var pattern: Node2D = testbed.get("_pattern")
		if int(testbed.get("source")) == 1:
			for index in 5:
				var rect := Rect2(1002.0 + float(index) * 51.0, 420.0, 42.0, 42.0)
				var transform := pattern.get_global_transform_with_canvas()
				_polygons.append(PackedVector2Array([
					transform * rect.position, transform * Vector2(rect.end.x, rect.position.y),
					transform * rect.end, transform * Vector2(rect.position.x, rect.end.y),
				]))
				_colors.append(Color.WHITE if mode == 0 else Color(0.5, 0.5, 0.0).linear_to_srgb())
		else:
			_add_circle(Transform2D(0.0, get_viewport_rect().size * 0.5), get_viewport_rect().size.y * 0.22,
				Color.WHITE if mode == 0 else Color(0.5, 0.5, 0.0))
	for id: int in _previous.keys():
		if not _seen.has(id):
			_previous.erase(id)
	queue_redraw()


func _add_visual(visual: Node2D) -> void:
	if not visual.is_visible_in_tree():
		return
	var transform := visual.get_global_transform_with_canvas()
	var id := visual.get_instance_id()
	_seen[id] = true
	var old: Vector2 = _previous.get(id, transform.origin)
	_previous[id] = transform.origin
	var velocity := (transform.origin - old) / get_viewport_rect().size
	var color := Color.WHITE if mode == 0 else Color(clampf(0.5 + velocity.x * 8.0, 0.0, 1.0), clampf(0.5 + velocity.y * 8.0, 0.0, 1.0), 1.0)
	_add_circle(transform, float(visual.get("radius")), color)


func _add_circle(transform: Transform2D, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in 48:
		points.append(transform * (Vector2.RIGHT.rotated(TAU * float(index) / 48.0) * radius))
	_polygons.append(points)
	_colors.append(color.linear_to_srgb())


func _draw() -> void:
	var background := Color.BLACK if mode == 0 else Color(0.5, 0.5, 0.0)
	draw_rect(get_viewport_rect(), background.linear_to_srgb())
	for index in _polygons.size():
		draw_colored_polygon(_polygons[index], _colors[index])
