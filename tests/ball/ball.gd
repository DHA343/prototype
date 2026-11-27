@tool
extends PinballBall

signal traveled(start: Vector2, end: Vector2, start_time: float, end_time: float)
signal repositioned

enum Finish {
	SINGLE_BAND,
	FAST_NOISE,
}

const BallVisual = preload("res://tests/ball/ball_visual.gd")
const BallOutline = preload("res://tests/ball/ball_outline.gd")
const BallAura = preload("res://tests/ball/ball_aura.gd")
const FINISHES: Array[ShaderMaterial] = [
	preload("res://tests/ball/silver_band.tres"),
	preload("res://tests/ball/fast_noise_gradient.tres"),
]
const MAX_ROLL_SPEED: float = 36.0

@export_group("Appearance")
@export var finish: Finish = Finish.SINGLE_BAND:
	set(value):
		finish = value
		if is_node_ready() and not Engine.is_editor_hint():
			_sphere.finish = FINISHES[finish]
@export var outline_enabled: bool = false:
	set(value):
		outline_enabled = value
		if is_node_ready() and not Engine.is_editor_hint():
			_outline.visible = outline_enabled
@export var aura_enabled: bool = false:
	set(value):
		aura_enabled = value
		if is_node_ready() and not Engine.is_editor_hint():
			_aura.visible = aura_enabled
			_aura.set_velocity(velocity)

var _segments: PackedVector2Array
var _distance: float

@onready var _sphere: BallVisual = $Sphere
@onready var _outline: BallOutline = $Outline
@onready var _aura: BallAura = $Aura


func _ready() -> void:
	if not Engine.is_editor_hint():
		var motion := ObservedMotion.new(self)
		motion.traveled.connect(_on_traveled)
		_motion = motion
		_sphere.finish = FINISHES[finish]
		_outline.visible = outline_enabled
		_aura.visible = aura_enabled
	super._ready()


func _draw() -> void:
	if Engine.is_editor_hint():
		super._draw()


func reset_at(point: Vector2, initial_velocity: Vector2 = Vector2.ZERO) -> void:
	super.reset_at(point, initial_velocity)
	_segments.clear()
	_distance = 0.0
	_sphere.reset_roll()
	_aura.set_velocity(velocity)
	repositioned.emit()


func advance(
	delta: float, swings: Array[PinballFlipper.Swing] = [], enemies: Array[Enemy] = [],
) -> void:
	super.advance(delta, swings, enemies)
	if active:
		_finish_visual_step(delta)


func _refresh_shape() -> void:
	super._refresh_shape()
	if is_node_ready() and not Engine.is_editor_hint():
		_sphere.radius = radius
		_outline.radius = radius
		_aura.radius = radius


func _on_traveled(start: Vector2, end: Vector2) -> void:
	var travel := end - start
	if travel.is_zero_approx():
		return
	_segments.append(travel)
	_distance += travel.length()
	traveled.emit(
		start, end, _motion.segment_start_time, _motion.elapsed_in_step,
	)


func _finish_visual_step(delta: float) -> void:
	if _distance > 0.0:
		# Limit rotation at pinball speeds while retaining the direction of every segment.
		var max_travel := radius * MAX_ROLL_SPEED * delta
		var factor := minf(1.0, max_travel / _distance)
		for travel in _segments:
			_sphere.roll(travel * factor)
	_segments.clear()
	_distance = 0.0
	if aura_enabled:
		_aura.set_velocity(velocity)


class ObservedMotion extends PinballMotion:
	signal traveled(start: Vector2, end: Vector2)


	func _init(target: CharacterBody2D) -> void:
		super._init(target)


	func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
		var previous := segment_traveled
		segment_traveled = _report_travel.bind(previous)
		super.advance(delta, swings)
		segment_traveled = previous


	func _report_travel(start: Vector2, end: Vector2, previous: Callable) -> void:
		if previous.is_valid():
			previous.call(start, end)
		traveled.emit(start, end)
