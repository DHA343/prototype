class_name CameraShake
extends Node

@export var max_offset: Vector2 = Vector2(16.0, 9.0)

@export_range(0.0, 10.0, 0.1)
var trauma_decay_rate: float = 3.0

@export_range(1.0, 4.0, 0.1)
var trauma_power: float = 2.0

@export_range(0.0, 100.0, 1.0)
var noise_speed: float = 30.0

@export_range(0.0, 0.2, 0.01)
var trauma_dead_zone: float = 0.02

var _trauma: float = 0.0
var _noise_position: float = 0.0
var _noise: FastNoiseLite
var _camera: Camera2D


func _ready() -> void:
	_camera = get_parent() as Camera2D
	assert(_camera != null, "CameraShake must be a child of Camera2D.")

	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	_noise.frequency = 1.0
	_noise.seed = randi()
	_camera.offset = Vector2.ZERO
	set_process(false)


func _exit_tree() -> void:
	if _camera != null:
		_camera.offset = Vector2.ZERO


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - trauma_decay_rate * delta, 0.0)
	if _trauma <= trauma_dead_zone:
		stop()
		return

	_noise_position += noise_speed * delta
	var shake_offset := Vector2(
		_noise.get_noise_1d(_noise_position),
		_noise.get_noise_1d(_noise_position + 1000.0)
	)
	var shake_strength := pow(_trauma, trauma_power)
	_camera.offset = shake_offset * max_offset * shake_strength


func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return

	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	set_process(true)


func stop() -> void:
	_trauma = 0.0
	_noise_position = 0.0
	_camera.offset = Vector2.ZERO
	set_process(false)
