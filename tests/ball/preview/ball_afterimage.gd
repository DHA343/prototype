extends Node2D

const AfterimageStyle = preload("res://tests/ball/preview/afterimage_style.gd")
const STAMP_SHADER: Shader = preload("res://tests/ball/preview/afterimage_stamp.gdshader")

var ball: PinballBall
var radius: float = 24.0
var gradient_enabled: bool = true
var style: AfterimageStyle

var _palette: GradientTexture1D
var _stamp_material: ShaderMaterial
var _stamps: Array[Stamp]
var _elapsed: float
var _physics_delta: float
var _sample_progress: float


func _ready() -> void:
	_palette = GradientTexture1D.new()
	_stamp_material = ShaderMaterial.new()
	_stamp_material.shader = STAMP_SHADER
	_stamp_material.set_shader_parameter(&"gradient_enabled", gradient_enabled)
	material = _stamp_material
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	style.changed.connect(_on_style_changed)
	_on_style_changed()


func _process(_delta: float) -> void:
	if not _stamps.is_empty() and ball.is_physics_interpolated_and_enabled():
		queue_redraw()


func _physics_process(delta: float) -> void:
	_physics_delta = delta
	_elapsed += delta
	if _stamps.is_empty():
		return

	# Keep any stamps the next interpolated frame can still show.
	var oldest_visible := _elapsed - delta - style.lifetime
	while not _stamps.is_empty() and _stamps[0].born_at <= oldest_visible:
		_stamps.pop_front()
	queue_redraw()


func _draw() -> void:
	var display_time := _elapsed
	if ball.is_physics_interpolated_and_enabled():
		display_time -= _physics_delta * (1.0 - Engine.get_physics_interpolation_fraction())

	var taper_duration := style.lifetime - style.width_hold
	for stamp in _stamps:
		if stamp.born_at > display_time:
			break
		var time_left := style.lifetime - (display_time - stamp.born_at)
		var freshness := clampf(time_left / style.lifetime, 0.0, 1.0)
		var width_freshness := 1.0
		if taper_duration > 0.0:
			width_freshness = clampf(time_left / taper_duration, 0.0, 1.0)
		var stamp_radius := radius * style.width_scale * lerpf(0.18, 1.0, width_freshness)
		var extent := Vector2.ONE * stamp_radius
		var rect := Rect2(to_local(stamp.point) - extent, extent * 2.0)
		draw_texture_rect(_palette, rect, false, Color(1.0, 1.0, 1.0, freshness))


func record_travel(start: Vector2, end: Vector2, start_time: float, end_time: float) -> void:
	var travel := end - start
	var distance := travel.length()
	if is_zero_approx(distance):
		return

	var spacing := radius / 3.0
	var offset := spacing - _sample_progress
	while offset <= distance:
		var fraction := offset / distance
		var born_at := _elapsed + lerpf(start_time, end_time, fraction)
		_stamps.append(Stamp.new(start + travel * fraction, born_at))
		offset += spacing
	_sample_progress = fposmod(_sample_progress + distance, spacing)
	queue_redraw()


func clear() -> void:
	_stamps.clear()
	_elapsed = 0.0
	_sample_progress = 0.0
	queue_redraw()


func _on_style_changed() -> void:
	_palette.gradient = style.color_gradient
	_stamp_material.set_shader_parameter(&"base_opacity", style.opacity)
	_stamp_material.set_shader_parameter(&"root_color_hold", style.root_color_hold)
	_stamp_material.set_shader_parameter(&"edge_color_strength", style.edge_color_strength)
	queue_redraw()


class Stamp:
	var point: Vector2
	var born_at: float

	func _init(world_point: Vector2, time: float) -> void:
		point = world_point
		born_at = time
