@tool
class_name Missile
extends Projectile
## 横ずれした狙い点への追尾、加速度制限、断続的な操舵誤差を扱う。

const SEED_SCALE: float = 1000000.0
const INSTABILITY_SEED_OFFSET: int = 173
const OFFSET_SEED_OFFSET: int = 7919

@export_group("Flight")
@export_range(3.0, 1500.0, 3.0, "suffix:px/s") var speed: float = 750.0
## 0で従来の速度ベクトル更新を使う。実際の飛行方向の角速度を制限する。
@export_range(0.0, 720.0, 15.0, "suffix:°/s") var max_turn_speed: float = 0.0
@export_group("Acceleration", "acceleration_")
## 旋回も含めた、実速度の1秒あたりの最大変化量。
@export_range(300.0, 18000.0, 300.0, "suffix:px/s²") var acceleration_limit: float = 5400.0
@export_range(0.02, 1.0, 0.01, "suffix:s") var acceleration_response_time: float = 0.08
@export_group("Speed Control", "speed_control_")
## 旋回角がTurn Angle以上のときに使う、指示速度に対する割合。100%で旋回減速を無効にする。
@export_range(10.0, 100.0, 1.0, "suffix:%") var speed_control_turn_speed: float = 45.0
## 現在の速度方向と操舵方向の差がこの角度で、旋回減速を最大にする。
@export_range(1.0, 180.0, 1.0, "suffix:°") var speed_control_turn_angle: float = 90.0
@export_group("Offset", "offset_")
@export_range(0.0, 900.0, 15.0, "suffix:px") var offset_max_distance: float = 360.0
@export_range(30.0, 1500.0, 30.0, "suffix:px") var offset_fade_distance: float = 540.0
## 実目標までの距離がこの値以下なら、横ずれを0にする。
## Fade Distance以上に設定すると減衰区間がなくなり、この距離を境に切り替わる。
@export_range(0.0, 1500.0, 3.0, "suffix:px") var offset_zero_distance: float = 0.0
## 距離比に適用する指数。1で線形、2で二乗。大きいほど接近時の横ずれを早く小さくする。
@export_range(0.1, 4.0, 0.1) var offset_power: float = 2.0
## 横ずれを加えずに目標を直接狙う確率。操舵誤差は引き続き適用する。
@export_range(0.0, 100.0, 1.0, "suffix:%") var offset_direct_chance: float = 25.0

@export_group("Instability", "instability_")
@export var instability_enabled: bool = true:
	set(value):
		instability_enabled = value
		notify_property_list_changed()
## 誤差イベントごとに、この範囲内から符号付きの最大操舵角を一様抽選する。
@export_range(0.0, 90.0, 1.0, "suffix:°") var instability_angle: float = 45.0
## 抽選した角度を保持する時間。
@export_range(0.0, 0.8, 0.01, "suffix:s") var instability_hold_min: float = 0.02
@export_range(0.0, 0.8, 0.01, "suffix:s") var instability_hold_max: float = 0.12
@export_range(0.0, 1.0, 0.01, "suffix:s") var instability_rest_min: float = 0.03
@export_range(0.0, 1.0, 0.01, "suffix:s") var instability_rest_max: float = 0.20
## 個々の誤差イベントとは独立して、追尾開始から誤差全体の影響を線形に立ち上げる。
@export_range(0.0, 0.6, 0.01, "suffix:s") var instability_fade_in: float = 0.15
## この距離から命中半径までの間で、誤差の影響を線形に0へ近づける。
@export_range(24.0, 360.0, 3.0, "suffix:px") var instability_capture_distance: float = 135.0

var desired_speed: float = 0.0

var _homing_elapsed: float = 0.0
var _straight_direction: Vector2 = Vector2.DOWN
var _flight_direction: Vector2 = Vector2.DOWN

var _has_guidance: bool = false
var _guidance_origin: Vector2 = Vector2.ZERO
var _guidance_target: Vector2 = Vector2.ZERO
var _aim_position: Vector2 = Vector2.ZERO
var _offset_factor: float = 0.0
var _steering_direction: Vector2 = Vector2.ZERO
var _applied_instability_angle: float = 0.0

var _instability_random: RandomNumberGenerator = RandomNumberGenerator.new()
var _instability_elapsed: float = 0.0
var _instability_rest_duration: float = 0.0
var _instability_hold_duration: float = 0.0
var _sampled_instability_angle: float = 0.0
var _instability_angle: float = 0.0

static func lateral_offset_weight(
	distance: float, zero_distance: float, fade_distance: float, power: float,
) -> float:
	var ratio := 0.0
	if distance > zero_distance:
		ratio = 1.0
		if fade_distance > zero_distance:
			ratio = clampf((distance - zero_distance) / (fade_distance - zero_distance), 0.0, 1.0)
	return pow(ratio, power)


func _validate_property(property: Dictionary) -> void:
	var property_name: String = property.name
	if property_name.begins_with("instability_") and property_name != "instability_enabled" and not instability_enabled:
		property.usage &= ~PROPERTY_USAGE_EDITOR


func advance(delta: float, enemies: Array[Enemy] = []) -> void:
	if not active:
		return
	if state != State.STRAIGHT and get_target() == null:
		fly_straight(_velocity.normalized())

	var previous_position := position
	var previous_global_position := global_position
	_advance_flight(delta)
	_age += delta

	var target := get_target()
	if piercing:
		_check_penetration(previous_global_position, enemies)
		if not active:
			return
	elif target != null:
		var target_position := _get_target_position()
		var closest_position := Geometry2D.get_closest_point_to_segment(
			target_position, previous_position, position)
		var contact_radius := hit_radius + target.radius
		if closest_position.distance_squared_to(target_position) <= contact_radius * contact_radius:
			target.receive_hit(damage, global_position, Vector2.ZERO)
			_finish_flight(true)
			return

	if _age >= lifetime:
		_finish_flight(false)


func launch(
	origin: Vector2, direction: Vector2, target: Enemy, seed_value: float, initial_speed: float,
) -> void:
	_begin_flight(origin, direction, seed_value)
	_target = target
	_velocity = direction.normalized() * clampf(initial_speed, 0.0, speed)
	desired_speed = clampf(initial_speed, 0.0, speed)
	_homing_elapsed = 0.0
	fly_straight(direction)
	_reset_instability(seed_value)
	_choose_lateral_offset(seed_value)
	_start_visuals()


func fly_straight(direction: Vector2) -> void:
	state = State.STRAIGHT
	_straight_direction = direction.normalized()
	_flight_direction = _straight_direction
	_steering_direction = _straight_direction
	_has_guidance = false
	_applied_instability_angle = 0.0


func start_homing(target: Enemy) -> void:
	if state == State.STRAIGHT:
		_homing_elapsed = 0.0
	state = State.HOMING
	_target = target


func refresh_guidance() -> void:
	# 停止中も狙い点を更新するが、飛行・誤差イベント・乱数は進めない。
	if state == State.STRAIGHT or not _has_guidance:
		return

	_update_aim_position()
	_update_steering_direction(_homing_elapsed)


## 直前の追尾計算に使った状態を返す。移動後の位置から狙い点を再計算しない。
func get_guidance_state() -> Dictionary:
	if not _has_guidance:
		return {}

	return {
		"state": state,
		"origin": _guidance_origin,
		"target": _guidance_target,
		"aim": _aim_position,
		"direction": _steering_direction,
		"instability_angle": _applied_instability_angle,
		"instability_active": _is_instability_active(),
		"instability_enabled": instability_enabled,
	}


func _advance_flight(delta: float) -> void:
	if state == State.HOMING:
		_update_aim_position()
		if instability_enabled:
			_update_instability(delta)
		_homing_elapsed += delta
		_update_steering_direction(_homing_elapsed)
	else:
		_steering_direction = _straight_direction

	var commanded_speed := clampf(desired_speed, 0.0, speed)
	var target_speed := _get_homing_speed(commanded_speed) if state == State.HOMING else commanded_speed
	_move_with_acceleration(delta, target_speed)


func _get_homing_speed(commanded_speed: float) -> float:
	var turn_speed := commanded_speed
	if not _velocity.is_zero_approx():
		var turn_angle := absf(_velocity.angle_to(_steering_direction))
		var turn_ratio := clampf(turn_angle / deg_to_rad(speed_control_turn_angle), 0.0, 1.0)
		turn_speed *= lerpf(1.0, speed_control_turn_speed / 100.0, turn_ratio)

	return turn_speed


func _move_with_acceleration(delta: float, target_speed: float) -> void:
	var desired_velocity := _steering_direction * target_speed
	var response := 1.0 - exp(-delta / acceleration_response_time)
	if max_turn_speed > 0.0 and state == State.HOMING:
		var direction := _velocity.normalized() if not _velocity.is_zero_approx() else _flight_direction
		var angle := direction.angle_to(_steering_direction) if not _steering_direction.is_zero_approx() else 0.0
		# 真後ろの左右は数学的に等価。浮動小数点の符号で反転しないようseed側で決める。
		if is_equal_approx(absf(angle), PI):
			angle = PI * (-signf(_offset_factor) if _offset_factor != 0.0 else 1.0)
		var turn_limit := deg_to_rad(max_turn_speed) * delta
		direction = direction.rotated(clampf(angle * response, -turn_limit, turn_limit))
		# 旋回制限中に逆向きベクトルへ補間して停止・反転することを避ける。
		desired_velocity = direction * lerpf(_velocity.length(), target_speed, response)
		response = 1.0
	var velocity_change := (desired_velocity - _velocity) * response

	var previous_velocity := _velocity
	_velocity += velocity_change.limit_length(acceleration_limit * delta)
	_velocity = _velocity.limit_length(speed)
	if max_turn_speed > 0.0 and not _velocity.is_zero_approx():
		_flight_direction = _velocity.normalized()
	position += (previous_velocity + _velocity) * (0.5 * delta)


func _choose_lateral_offset(seed_value: float) -> void:
	# 狙い点の抽選を操舵誤差のイベントから独立させるため、別の乱数列を使う。
	var offset_random := RandomNumberGenerator.new()
	offset_random.seed = int(seed_value * SEED_SCALE) + OFFSET_SEED_OFFSET
	var aims_directly := offset_random.randf() < offset_direct_chance / 100.0
	_offset_factor = 0.0 if aims_directly else offset_random.randf_range(-1.0, 1.0)


func _update_aim_position() -> void:
	_guidance_origin = position
	_guidance_target = _get_target_position()
	_aim_position = _get_lateral_aim_position()
	_has_guidance = true


func _get_lateral_aim_position() -> Vector2:
	var displacement := _guidance_target - _guidance_origin
	var weight := lateral_offset_weight(
		displacement.length(), offset_zero_distance, offset_fade_distance, offset_power)
	var lateral_distance := offset_max_distance * weight
	var lateral_direction := displacement.normalized().orthogonal()
	return _guidance_target + lateral_direction * lateral_distance * _offset_factor


func _update_steering_direction(homing_time: float) -> void:
	_applied_instability_angle = 0.0
	if instability_enabled:
		_applied_instability_angle = _instability_angle * _get_instability_influence(homing_time)

	var aim_direction := (_aim_position - _guidance_origin).normalized()
	_steering_direction = aim_direction.rotated(_applied_instability_angle)


func _reset_instability(seed_value: float) -> void:
	_instability_random.seed = int(seed_value * SEED_SCALE) + INSTABILITY_SEED_OFFSET
	_instability_elapsed = 0.0
	_instability_angle = 0.0
	_sample_instability_cycle()


func _sample_instability_cycle() -> void:
	_instability_rest_duration = _random_instability_duration(instability_rest_min, instability_rest_max)
	_sampled_instability_angle = deg_to_rad(instability_angle) * _instability_random.randf_range(-1.0, 1.0)
	_instability_hold_duration = _random_instability_duration(instability_hold_min, instability_hold_max)


func _update_instability(delta: float) -> void:
	var max_cycle_duration := maxf(instability_rest_min, instability_rest_max)
	max_cycle_duration += maxf(instability_hold_min, instability_hold_max)
	if max_cycle_duration <= 0.0:
		_instability_angle = 0.0
		return

	_instability_elapsed += delta
	var cycle_duration := _instability_rest_duration + _instability_hold_duration
	while _instability_elapsed >= cycle_duration:
		# 周期の余り時間を引き継ぐため、更新頻度で抽選時刻が変わらない。
		_instability_elapsed -= cycle_duration
		_sample_instability_cycle()
		cycle_duration = _instability_rest_duration + _instability_hold_duration

	_instability_angle = _sampled_instability_angle if _is_instability_active() else 0.0


func _is_instability_active() -> bool:
	return _instability_hold_duration > 0.0 and _instability_elapsed >= _instability_rest_duration


func _random_instability_duration(min_duration: float, max_duration: float) -> float:
	return _instability_random.randf_range(
		minf(min_duration, max_duration), maxf(min_duration, max_duration))


func _get_instability_influence(homing_time: float) -> float:
	var onset_weight := 1.0
	if instability_fade_in > 0.0:
		onset_weight = clampf(homing_time / instability_fade_in, 0.0, 1.0)

	var fade_start_distance := maxf(instability_capture_distance, hit_radius + 0.001)
	var distance := position.distance_to(_get_target_position())
	var distance_weight := clampf(
		(distance - hit_radius) / (fade_start_distance - hit_radius), 0.0, 1.0)
	return onset_weight * distance_weight
