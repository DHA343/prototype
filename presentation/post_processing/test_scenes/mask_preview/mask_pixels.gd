extends Control

signal pixel_selected(pixel: Vector2i)

var texture: Texture2D
var zoom: int = 12
var grid_enabled: bool = true
var selected_pixel: Vector2i = Vector2i.ZERO

var _image_origin: Vector2 = Vector2.ZERO


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	resized.connect(queue_redraw)
	update_size()


func _draw() -> void:
	if texture == null:
		return
	var extent := Vector2(texture.get_size()) * float(zoom)
	_image_origin = Vector2(maxf(0.0, floorf((size.x - extent.x) * 0.5)), 0.0)
	draw_texture_rect(texture, Rect2(_image_origin, extent), false)
	var grid_color := get_theme_color("font_color", "Label")
	if grid_enabled:
		grid_color.a = 0.22
		for column: int in range(texture.get_width() + 1):
			var x := float(column * zoom)
			draw_line(_image_origin + Vector2(x, 0.0), _image_origin + Vector2(x, extent.y), grid_color)
		for row: int in range(texture.get_height() + 1):
			var y := float(row * zoom)
			draw_line(_image_origin + Vector2(0.0, y), _image_origin + Vector2(extent.x, y), grid_color)
	var selection := Rect2(
		_image_origin + Vector2(selected_pixel) * float(zoom), Vector2.ONE * float(zoom),
	)
	draw_rect(selection.grow(-1.0), Color.BLACK, false, 3.0)
	draw_rect(selection.grow(-1.0), get_theme_color("font_color", "Label"), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if texture == null:
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var local_position: Vector2 = event.position - _image_origin
		if not Rect2(Vector2.ZERO, Vector2(texture.get_size()) * float(zoom)).has_point(local_position):
			return
		select_pixel(Vector2i((local_position / float(zoom)).floor()))
		if event is InputEventMouseButton and event.pressed:
			grab_focus()
		return
	if event is InputEventKey and event.pressed:
		var offset := Vector2i.ZERO
		match event.keycode:
			KEY_LEFT:
				offset = Vector2i.LEFT
			KEY_RIGHT:
				offset = Vector2i.RIGHT
			KEY_UP:
				offset = Vector2i.UP
			KEY_DOWN:
				offset = Vector2i.DOWN
		if offset != Vector2i.ZERO:
			select_pixel(selected_pixel + offset)
			accept_event()


func update_size() -> void:
	if texture != null:
		custom_minimum_size = Vector2(texture.get_size()) * float(zoom)
	queue_redraw()


func select_pixel(pixel: Vector2i) -> void:
	selected_pixel = pixel.clamp(Vector2i.ZERO, Vector2i(texture.get_size()) - Vector2i.ONE)
	pixel_selected.emit(selected_pixel)
	queue_redraw()
