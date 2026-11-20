@tool
extends Missile
## 正弦波で操舵し、追尾対象への命中後は離脱してから再追尾する。

# 旋回上限を外したときも、旧版が半回転する時間（180° / 540°/秒）は離脱を続ける。
const UNLIMITED_DEPARTURE_DURATION: float = 180.0 / 540.0

@export var constant_speed: bool = true
@export_range(0.0, 90.0, 1.0, "suffix:°") var wobble_angle: float = 18.0
@export_range(0.0, 10.0, 0.1, "suffix:Hz") var wobble_frequency: float = 2.5
## 命中時の距離から、再追尾までにさらに離れる距離。
@export_range(0.0, 150.0, 1.0, "suffix:px") var departure_distance: float = 30.0

var _launch_initial_speed: float = 0.0
var _launch_deceleration: float = 0.0
var _launch_brake_time: float = 0.0
var _launch_transition_time: float = 0.0
var _launch_heading: Vector2 = Vector2.ZERO
var _transition_origin: Vector2 = Vector2.ZERO
var _transition_speed: float = 0.0
var _launch_transition_pending: bool = false

var _wobble_time: float = 0.0
var _wobble_phase: float = 0.0
var _wobble_random: RandomNumberGenerator = RandomNumberGenerator.new()
var lateral_wobble_width: float = 0.0
var lateral_wobble_wavelength: float = 300.0
var _baseline_position: Vector2 = Vector2.ZERO
var _baseline_distance: float = 0.0
var _departing_target: Enemy
var _departure_end_distance: float = 0.0
var _departure_end_age: float = 0.0


func launch(
	origin: Vector2, direction: Vector2, target: Enemy, seed_value: float, initial_speed: float,
) -> void:
	super.launch(origin, direction, target, seed_value, speed if constant_speed else initial_speed)
	_launch_heading = _flight_direction
	_launch_transition_pending = _launch_brake_time > 0.0
	if _launch_brake_time > 0.0:
		_velocity = _straight_direction * _launch_initial_speed
	_wobble_random.seed = int(seed_value * SEED_SCALE) + 130363
	_wobble_phase = _wobble_random.randf_range(0.0, TAU)
	_wobble_time = 0.0
	_baseline_position = origin
	_baseline_distance = 0.0
	_departing_target = null
	_departure_end_distance = 0.0
	_departure_end_age = 0.0


func configure_launch(
	initial_speed: float, deceleration: float, brake_time: float, transition_time: float,
) -> void:
	_launch_initial_speed = initial_speed
	_launch_deceleration = deceleration
	_launch_brake_time = brake_time
	_launch_transition_time = transition_time


func retarget(target: Enemy) -> void:
	_target = target


func get_body_direction() -> Vector2:
	if _launch_transition_pending:
		if state == State.STRAIGHT:
			return _launch_heading
		var weight := smoothstep(0.0, _launch_transition_time, _homing_elapsed)
		return _launch_heading.slerp(_flight_direction, weight)
	return super.get_body_direction()


func should_emit_exhaust() -> bool:
	return not (_launch_transition_pending and state == State.STRAIGHT)


func get_guidance_state() -> Dictionary:
	var snapshot := super.get_guidance_state()
	if not snapshot.is_empty():
		snapshot.merge({
			"method": "missile", "velocity": _velocity,
			"noise_angle": _applied_instability_angle,
			"angle_max": deg_to_rad(wobble_angle), "frequency": wobble_frequency,
			"departing": is_instance_valid(_departing_target),
		}, true)
		if lateral_wobble_width > 0.0:
			snapshot["method"] = "lateral_wobble"
			snapshot["baseline"] = _baseline_position
			snapshot["body"] = position
	return snapshot


func _advance_flight(delta: float) -> void:
	if _launch_brake_time > 0.0 and _wobble_time < _launch_brake_time:
		var braking_step := minf(delta, _launch_brake_time - _wobble_time)
		var start := _wobble_time
		_wobble_time = minf(start + braking_step, _launch_brake_time)
		position += _straight_direction * (_launch_distance_at(_wobble_time) - _launch_distance_at(start))
		_baseline_position = position
		_velocity = _straight_direction * _launch_speed_at(_wobble_time)
		if get_target() != null:
			var target_direction := position.direction_to(_get_target_position())
			if not target_direction.is_zero_approx():
				var weight := smoothstep(0.0, _launch_brake_time, _wobble_time)
				var angle := lerp_angle(_straight_direction.angle(), target_direction.angle(), weight)
				_launch_heading = _turned_direction(
					_launch_heading, Vector2.from_angle(angle), braking_step,
				)
		delta -= braking_step
		if delta <= 0.000001:
			return
	if _launch_transition_time > 0.0 and state == State.STRAIGHT and get_target() != null:
		if _velocity.is_zero_approx():
			_flight_direction = _launch_heading
		_transition_origin = _flight_direction
		_transition_speed = _velocity.length()
		start_homing(get_target())
	_wobble_time += delta
	if lateral_wobble_width > 0.0 and state == State.STRAIGHT:
		_baseline_position = position
	if is_instance_valid(_departing_target):
		var target := get_target()
		var reached_distance := global_position.distance_to(
			_departing_target.global_position) >= _departure_end_distance
		if target != _departing_target or (reached_distance and _age >= _departure_end_age):
			_departing_target = null
	super._advance_flight(delta)


func _on_penetration(enemy: Enemy) -> void:
	if state != State.HOMING or enemy != get_target() or is_instance_valid(_departing_target):
		return
	_departing_target = enemy
	_departure_end_distance = global_position.distance_to(enemy.global_position) + departure_distance
	_departure_end_age = _age + UNLIMITED_DEPARTURE_DURATION if max_turn_speed <= 0.0 else _age


func _get_homing_speed(commanded_speed: float) -> float:
	return speed if constant_speed else commanded_speed


func _move_with_acceleration(delta: float, target_speed: float) -> void:
	if state == State.STRAIGHT:
		if _launch_transition_time > 0.0:
			position += _velocity * delta
		elif constant_speed:
			_velocity = _flight_direction * speed
			position += _velocity * delta
		else:
			super._move_with_acceleration(delta, target_speed)
		return
	# 追尾中は角度だけを上限内で回し、旋回で減速しない。
	if _launch_transition_pending:
		var weight := smoothstep(0.0, _launch_transition_time, _homing_elapsed)
		var aim := _launch_heading.slerp(_steering_direction, weight)
		var heading := _transition_origin.slerp(aim, weight)
		var previous_velocity := _velocity
		_flight_direction = _turned_direction(_flight_direction, heading, delta)
		var current_speed := lerpf(_transition_speed, target_speed, weight)
		_velocity = _flight_direction * current_speed
		position += (previous_velocity + _velocity) * (0.5 * delta)
		_launch_transition_pending = _homing_elapsed < _launch_transition_time
		_baseline_position = position
		return
	_flight_direction = _turned_direction(_flight_direction, _steering_direction, delta)
	_velocity = _flight_direction * target_speed
	if lateral_wobble_width > 0.0:
		var travel := target_speed * delta
		_baseline_position += _flight_direction * travel
		_baseline_distance += travel
		var phase := TAU * _baseline_distance / lateral_wobble_wavelength + _wobble_phase
		var fade := smoothstep(_launch_transition_time, _launch_transition_time + 0.15, _homing_elapsed)
		var next_position := _baseline_position + _flight_direction.orthogonal() * (
			lateral_wobble_width * fade * sin(phase)
		)
		_velocity = (next_position - position) / delta
		position = next_position
		return
	position += _velocity * delta


func _turned_direction(from: Vector2, direction: Vector2, turn_time: float) -> Vector2:
	if direction.is_zero_approx():
		return from
	var desired_angle := direction.angle()
	var turn := deg_to_rad(max_turn_speed) * turn_time
	var angle := desired_angle if max_turn_speed <= 0.0 \
		else rotate_toward(from.angle(), desired_angle, turn)
	return Vector2.from_angle(angle)


func _launch_speed_at(elapsed: float) -> float:
	return maxf(0.0, _launch_initial_speed - _launch_deceleration * elapsed)


func _launch_distance_at(elapsed: float) -> float:
	var moving_time := elapsed
	if _launch_deceleration > 0.0:
		moving_time = minf(moving_time, _launch_initial_speed / _launch_deceleration)
	var average_speed := (_launch_initial_speed + _launch_speed_at(moving_time)) * 0.5
	return moving_time * average_speed


func _update_aim_position() -> void:
	_guidance_origin = _baseline_position if lateral_wobble_width > 0.0 else position
	_guidance_target = _get_target_position()
	_aim_position = _guidance_target
	if is_instance_valid(_departing_target):
		_aim_position = 2.0 * _guidance_origin - _guidance_target
	_has_guidance = true


func _update_steering_direction(_homing_time: float) -> void:
	var direction := _guidance_origin.direction_to(_aim_position)
	if direction.is_zero_approx():
		_applied_instability_angle = 0.0
		_steering_direction = _flight_direction
		return
	_applied_instability_angle = 0.0
	if lateral_wobble_width <= 0.0:
		var phase := _wobble_time * wobble_frequency * TAU + _wobble_phase
		_applied_instability_angle = deg_to_rad(wobble_angle) * sin(phase)
	_steering_direction = direction.rotated(_applied_instability_angle)
