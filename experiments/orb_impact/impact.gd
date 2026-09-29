extends Node2D

@export_group("Spark")
@export var spark_color: Color = Color(1.0, 0.92, 0.65)
@export_range(3, 12, 1) var spark_count: int = 6
@export_range(0.08, 0.4, 0.01, "suffix:s") var spark_duration: float = 0.18
@export_range(20.0, 140.0, 1.0, "suffix:px") var spark_distance: float = 72.0
@export_range(4.0, 40.0, 1.0, "suffix:px") var spark_length: float = 22.0
@export_range(1.0, 8.0, 0.5, "suffix:px") var spark_width: float = 5.0
@export_group("Ring")
@export var ring_color: Color = Color(0.8, 0.95, 1.0)
@export_range(0.08, 0.4, 0.01, "suffix:s") var ring_duration: float = 0.2
@export_range(10.0, 100.0, 1.0, "suffix:px") var ring_radius: float = 48.0
@export_range(1.0, 6.0, 0.5, "suffix:px") var ring_width: float = 2.5

var _age: float = 0.0
var _strength: float = 1.0
var _sparks_enabled: bool = true
var _ring_enabled: bool = false
var _directions: Array[Vector2] = []
var _distances: Array[float] = []


func _process(delta: float) -> void:
	_age += delta
	if _age >= maxf(spark_duration, ring_duration):
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	if _sparks_enabled and _age < spark_duration:
		_draw_sparks()
	if _ring_enabled and _age < ring_duration:
		var progress := _age / ring_duration
		var radius := lerpf(7.0, ring_radius * _strength, 1.0 - pow(1.0 - progress, 3.0))
		var color := ring_color
		color.a *= pow(1.0 - progress, 1.5)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, color, ring_width, true)


func play(direction: Vector2, speed: float, sparks_enabled: bool, ring_enabled: bool) -> void:
	_sparks_enabled = sparks_enabled
	_ring_enabled = ring_enabled
	_strength = lerpf(0.65, 1.15, clampf(speed / 6000.0, 0.0, 1.0))
	for index in spark_count:
		var angle := lerpf(-1.15, 1.15, float(index) / float(spark_count - 1))
		_directions.append(direction.rotated(angle + randf_range(-0.12, 0.12)))
		_distances.append(randf_range(0.65, 1.0))
	queue_redraw()


func _draw_sparks() -> void:
	var progress := _age / spark_duration
	var travel := 1.0 - pow(1.0 - progress, 2.0)
	var color := spark_color
	color.a *= pow(1.0 - progress, 0.7)
	for index in _directions.size():
		var direction := _directions[index]
		var tip := direction * (6.0 + travel * spark_distance * _distances[index]) * _strength
		var length := spark_length * _strength * (1.0 - progress) * _distances[index]
		var tail := tip - direction * length
		var side := direction.orthogonal() * spark_width * 0.5 * _strength * (1.0 - progress)
		draw_colored_polygon(PackedVector2Array([tip, tail + side, tail - side]), color)
	if progress < 0.22:
		var flash := Color(1.0, 0.98, 0.85, 1.0 - progress / 0.22)
		draw_circle(Vector2.ZERO, 7.0 * _strength, flash, true, -1.0, true)
