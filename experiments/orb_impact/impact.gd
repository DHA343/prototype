extends Node2D

@export_group("Spark")
@export var spark_color: Color = Color(1.0, 0.86, 0.5)
@export_range(3, 12, 1) var spark_count: int = 6
@export_range(0.08, 0.4, 0.01, "suffix:s") var spark_duration: float = 0.19
@export_range(20.0, 140.0, 1.0, "suffix:px") var spark_distance: float = 80.0
@export_range(4.0, 40.0, 1.0, "suffix:px") var spark_length: float = 26.0
@export_range(1.0, 8.0, 0.5, "suffix:px") var spark_width: float = 5.0
@export_group("Wave")
@export_range(0.08, 0.2, 0.01, "suffix:s") var ring_duration: float = 0.13
@export_range(10.0, 100.0, 1.0, "suffix:px") var ring_radius: float = 48.0
@export_range(1.0, 2.0, 0.05) var ring_stretch: float = 1.45
@export_group("Droplets")
@export var droplet_color: Color = Color(0.18, 0.7, 0.92)
@export_range(0.1, 0.5, 0.01, "suffix:s") var droplet_duration: float = 0.28
@export_range(2.0, 12.0, 0.5, "suffix:px") var droplet_radius: float = 6.0

var wave_enabled: bool = false
var ring_enabled: bool = false
var distortion_enabled: bool = false
var _age: float = 0.0
var _strength: float = 1.0
var _speed_ratio: float = 0.0
var _sparks_enabled: bool = false
var _droplets_enabled: bool = false
var _direction: Vector2 = Vector2.RIGHT
var _directions: Array[Vector2] = []
var _distances: Array[float] = []
var _lifetimes: Array[float] = []


func _process(delta: float) -> void:
	_age += delta
	if _age >= maxf(droplet_duration, maxf(spark_duration * 1.15, ring_duration)):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _sparks_enabled:
		_draw_sparks()
	if _droplets_enabled:
		_draw_droplets()


func play(direction: Vector2, speed: float, mode: int) -> void:
	_direction = direction.normalized()
	_speed_ratio = clampf(speed / 6000.0, 0.0, 1.0)
	_strength = lerpf(0.65, 1.15, _speed_ratio)
	_sparks_enabled = mode in [0, 2]
	ring_enabled = mode in [1, 2, 4]
	distortion_enabled = mode in [4, 5]
	wave_enabled = ring_enabled or distortion_enabled
	_droplets_enabled = mode == 6
	for index in spark_count:
		var angle := lerpf(-1.1, 1.1, float(index) / float(spark_count - 1))
		_directions.append(_direction.rotated(angle + randf_range(-0.12, 0.12)))
		_distances.append(randf_range(0.7, 1.0))
		_lifetimes.append(randf_range(0.8, 1.15))
	queue_redraw()


func get_wave_geometry() -> Vector4:
	var progress := clampf(_age / ring_duration, 0.0, 1.0)
	var travel := 1.0 - pow(1.0 - progress, lerpf(2.0, 3.5, _speed_ratio))
	var radius := lerpf(5.0, ring_radius * _strength, travel)
	var center := global_position + _direction * travel * lerpf(3.0, 12.0, _speed_ratio)
	return Vector4(center.x, center.y, radius * lerpf(1.05, ring_stretch, _speed_ratio), radius)


func get_wave_fade() -> float:
	return pow(1.0 - clampf(_age / ring_duration, 0.0, 1.0), 1.2)


func get_wave_direction() -> Vector2:
	return _direction


func _draw_sparks() -> void:
	for index in _directions.size():
		var progress := _age / (spark_duration * _lifetimes[index])
		if progress >= 1.0:
			continue
		var prominent := index == 2 or index == 3
		var size := 1.15 if prominent else 0.65
		var taper := 1.0 - smoothstep(0.2, 1.0, progress)
		# Avoid degenerate triangles after the spark becomes subpixel-sized.
		if taper < 0.03:
			continue
		var direction := _directions[index]
		var travel := (1.0 - pow(1.0 - progress, 2.0)) * spark_distance * _distances[index]
		var tip := direction * (10.0 + travel) * _strength
		var tail := tip - direction * spark_length * size * _strength * taper
		var side := direction.orthogonal() * spark_width * 0.5 * size * _strength * taper
		var color := spark_color
		color.a = taper
		draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), color)
		draw_line(tail.lerp(tip, 0.4), tip, Color(1.0, 0.98, 0.88, taper), 1.5 * size, true)
	if _age < 0.035:
		var flash := Color(1.0, 0.97, 0.8, 1.0 - _age / 0.035)
		draw_circle(Vector2.ZERO, 7.0 * _strength, flash, true, -1.0, true)


func _draw_droplets() -> void:
	for index in mini(5, _directions.size()):
		var progress := _age / (droplet_duration * minf(_lifetimes[index], 1.0))
		if progress >= 1.0:
			continue
		var direction := _directions[index]
		if index == 0:
			direction = -direction
		var travel := 1.0 - pow(1.0 - progress, 3.0)
		var center := direction * (9.0 + 60.0 * travel * _distances[index]) * _strength
		var size := 1.0 if index in [1, 3] else 0.55
		var radius := droplet_radius * size * _strength
		var fade := 1.0 - smoothstep(0.45, 1.0, progress)
		var color := droplet_color
		color.a = fade
		var stretch := lerpf(1.9, 1.0, smoothstep(0.0, 0.65, progress))
		draw_set_transform(center, direction.angle(), Vector2(stretch, 1.0) * lerpf(1.0, 0.65, progress))
		draw_circle(Vector2.ZERO, radius, color, true, -1.0, true)
		draw_circle(
			Vector2(-radius * 0.15, -radius * 0.3),
			radius * 0.28,
			Color(0.8, 1.0, 1.0, fade * 0.85),
			true, -1.0, true
		)
		draw_set_transform(Vector2.ZERO)
