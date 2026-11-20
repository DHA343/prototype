extends Node2D
## 本体・排気・煙・着弾演出を所有し、本体消滅後も残った演出を再生する。

## 1920×1080のゲーム座標上で、従来の1ドットを3単位で表す。
const PIXEL_SIZE: float = 3.0

@export var show_halo: bool = true:
	set(value):
		show_halo = value
		if is_instance_valid(_particles):
			_particles.material.set_shader_parameter("show_halo", show_halo)

@export var circular_body: bool = false

var _source: WeakRef
var _get_velocity: Callable
var _get_body_direction: Callable
var _should_emit_exhaust: Callable
var _tint: Color = Color("e99cff")
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _body_position: Vector2 = Vector2.ZERO
var _body_direction: Vector2 = Vector2.ZERO
var _exhaust_remainder: float = 0.0
var _was_emitting_exhaust: bool = true
var _tail_elapsed: float = 0.0
var _following: bool = false
var _finished: bool = false

@onready var _particles: GPUParticles2D = $Particles


func _ready() -> void:
	# 粒子を、飛行中の本体の位置・回転から独立させる。
	top_level = true
	global_transform = Transform2D.IDENTITY


func _physics_process(delta: float) -> void:
	if not _following and not _finished:
		return
	if _following:
		_record_source()
	else:
		_tail_elapsed += delta

	if not _following and _tail_elapsed >= 1.2:
		queue_free()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and is_instance_valid(_particles):
		_particles.speed_scale = 0.0
	elif what == NOTIFICATION_UNPAUSED and is_instance_valid(_particles):
		_particles.speed_scale = 1.0


func _draw() -> void:
	if _following:
		_draw_body()


func follow(
	source: Node2D, get_velocity: Callable, seed_value: float, tint: Color,
	get_body_direction: Callable = Callable(), should_emit_exhaust: Callable = Callable(),
) -> void:
	_source = weakref(source)
	_get_velocity = get_velocity
	_get_body_direction = get_body_direction
	_should_emit_exhaust = should_emit_exhaust
	_tint = tint
	_random.seed = int(seed_value * 1000000.0) + 142857
	_body_position = source.global_position
	_body_direction = Vector2.ZERO
	_exhaust_remainder = 0.0
	_was_emitting_exhaust = not _should_emit_exhaust.is_valid() or _should_emit_exhaust.call()
	_tail_elapsed = 0.0
	_following = true
	_finished = false
	_particles.restart()
	_particles.material.set_shader_parameter("show_halo", show_halo)


func impact(point: Vector2) -> void:
	_emit_impact(point, _tint)


func finish(hit: bool) -> void:
	if not _following:
		return
	_record_source()
	if hit:
		_emit_impact(_body_position, _tint)
	var source := _source.get_ref() as Node2D
	_following = false
	_finished = true
	_get_velocity = Callable()
	_get_body_direction = Callable()
	_should_emit_exhaust = Callable()
	if source != null and source.get_parent() != null:
		# ミサイルを解放しても、残った煙と着弾粒子は寿命まで残す。
		reparent(source.get_parent(), true)
	_source = null


func _record_source() -> void:
	var source := _source.get_ref() as Node2D
	if source == null:
		_following = false
		return

	var previous_position := _body_position
	_body_position = source.global_position
	var direction: Vector2 = (
		_get_body_direction.call() if _get_body_direction.is_valid() else _get_velocity.call()
	)
	var space := source.get_parent() as Node2D
	if space != null:
		direction = space.to_global(direction) - space.global_position
	_body_direction = direction.normalized()

	var emitting: bool = not _should_emit_exhaust.is_valid() or _should_emit_exhaust.call()
	if emitting and _was_emitting_exhaust:
		_emit_exhaust(previous_position)
	else:
		_exhaust_remainder = 0.0
	_was_emitting_exhaust = emitting


func _emit_exhaust(previous_position: Vector2) -> void:
	var distance := previous_position.distance_to(_body_position)
	var direction := _body_direction
	var next_distance := PIXEL_SIZE - _exhaust_remainder
	while next_distance <= distance:
		var point := previous_position.lerp(_body_position, next_distance / distance) - direction * 9.0
		_emit_exhaust_particle(point, direction, _tint)
		next_distance += PIXEL_SIZE
	_exhaust_remainder = fmod(_exhaust_remainder + distance, PIXEL_SIZE)


func _draw_body() -> void:
	if circular_body:
		draw_circle(_body_position, PIXEL_SIZE * 2.0, _tint)
		return

	var direction := _body_direction
	for index in range(5, -1, -1):
		var point := (_body_position - direction * float(index) * PIXEL_SIZE).snapped(
			Vector2.ONE * PIXEL_SIZE)
		var color := _tint if index > 1 else Color("fff8dc")
		draw_rect(Rect2(point, Vector2.ONE * PIXEL_SIZE), color)
	var center := _body_position.snapped(Vector2.ONE * PIXEL_SIZE)
	draw_rect(Rect2(center - Vector2.ONE * PIXEL_SIZE, Vector2(9, 9)),
		_tint * Color(1, 1, 1, 0.3))
	draw_rect(Rect2(center, Vector2.ONE * PIXEL_SIZE), Color.WHITE)


func _emit_exhaust_particle(point: Vector2, velocity: Vector2, tint: Color) -> void:
	var drift := -velocity.normalized() * _random.randf_range(21, 60)
	drift += Vector2(_random.randf_range(-27, 27), _random.randf_range(-27, 27))
	_add_particle(point, drift, tint, _random.randf_range(0.3, 0.65), false)
	if _random.randf() < 0.18:
		_add_particle(point, drift * 0.3 + Vector2(0, -15), tint, _random.randf_range(0.45, 0.9), true)


func _emit_impact(point: Vector2, tint: Color) -> void:
	for index in range(36):
		var direction := Vector2.from_angle(_random.randf_range(0, TAU))
		_add_particle(point, direction * _random.randf_range(45, 315), tint, _random.randf_range(0.18, 0.65), false)
	for index in range(8):
		_add_particle(point, Vector2(_random.randf_range(-42, 42), _random.randf_range(-66, 0)), tint, 0.8, true)


func _add_particle(point: Vector2, velocity: Vector2, tint: Color, duration: float, smoke: bool) -> void:
	# 発生位置・乱数の順番は従来通りとし、その後の更新と描画をGPUへ渡す。
	var particle_size := float(_random.randi_range(1, 3)) * PIXEL_SIZE
	var custom := Color(duration, 0.0, 1.0 if smoke else 0.0, particle_size)
	var flags := GPUParticles2D.EMIT_FLAG_POSITION | GPUParticles2D.EMIT_FLAG_ROTATION_SCALE
	flags |= GPUParticles2D.EMIT_FLAG_VELOCITY | GPUParticles2D.EMIT_FLAG_COLOR | GPUParticles2D.EMIT_FLAG_CUSTOM
	_particles.emit_particle(Transform2D(0.0, point), velocity, tint, custom, flags)
