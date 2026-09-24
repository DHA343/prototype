class_name HammerVisual
extends Node2D

enum Phase {
	CHARGING,
	WINDUP,
	IMPACT,
}

const HAMMER_COLOR := Color(0.48, 0.27, 0.12)
const RAISED_ANGLE: float = -120.0
const SLAM_ANGLE: float = 15.0
const HAMMER_LENGTH: float = 50.0

@export_range(32.0, 200.0, 1.0, "suffix:unit") var streak_radius: float = 100.0
@export_range(1, 48, 1) var streak_count: int = 28

var _phase: Phase = Phase.CHARGING
var _windup_elapsed: float = 0.0
var _windup_duration: float = 0.1
var _impact_remaining: float = 0.12
var _facing_sign: float = 1.0
var _charge_sound: SoundCue
var _streaks: Array[Streak] = []
var _random := RandomNumberGenerator.new()

@onready var _audio_player: AudioStreamPlayer2D = $ChargeSound


func _process(delta: float) -> void:
	match _phase:
		Phase.CHARGING:
			_update_streaks(delta)
			if _charge_sound != null and _charge_sound.stream != null and not _audio_player.playing:
				_audio_player.play()
		Phase.WINDUP:
			_windup_elapsed = minf(_windup_elapsed + delta, _windup_duration)
		Phase.IMPACT:
			_impact_remaining -= delta
			modulate.a = clampf(_impact_remaining / 0.12, 0.0, 1.0)
			if _impact_remaining <= 0.0:
				queue_free()
	queue_redraw()


func _draw() -> void:
	if _phase == Phase.CHARGING:
		_draw_streaks()
	if _phase == Phase.WINDUP:
		_draw_swing_trail()
	_draw_hammer(_get_hammer_angle(), HAMMER_COLOR)


func begin_charge(direction: Vector2, cue: SoundCue) -> void:
	_charge_sound = cue
	set_aim_direction(direction)
	_random.randomize()
	_streaks.clear()
	for _index in streak_count:
		_streaks.append(_new_streak(true))
	if cue == null or cue.stream == null:
		return
	var stream: AudioStream = cue.stream
	var wav := stream as AudioStreamWAV
	if wav != null:
		var loop_wav := wav.duplicate() as AudioStreamWAV
		loop_wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		loop_wav.loop_begin = 0
		loop_wav.loop_end = int(round(loop_wav.get_length() * float(loop_wav.mix_rate)))
		stream = loop_wav
	_audio_player.stream = stream
	_audio_player.bus = cue.bus
	_audio_player.volume_db = cue.volume_db
	_audio_player.pitch_scale = cue.roll_pitch_scale()
	_audio_player.play()


func set_aim_direction(direction: Vector2) -> void:
	if direction.x > 0.15:
		_facing_sign = 1.0
	elif direction.x < -0.15:
		_facing_sign = -1.0


func begin_windup(direction: Vector2, duration: float) -> void:
	set_aim_direction(direction)
	_windup_duration = maxf(duration, 0.01)
	_windup_elapsed = 0.0
	_phase = Phase.WINDUP
	_audio_player.stop()


func impact() -> void:
	_phase = Phase.IMPACT
	_impact_remaining = 0.12


func _update_streaks(delta: float) -> void:
	for index in _streaks.size():
		var streak := _streaks[index]
		streak.radius -= streak.speed * delta
		if streak.radius <= 16.0:
			_streaks[index] = _new_streak(false)


func _new_streak(randomize_radius: bool) -> Streak:
	var streak := Streak.new()
	streak.angle = _random.randf_range(0.0, TAU)
	streak.radius = _random.randf_range(32.0, streak_radius) if randomize_radius else streak_radius
	streak.speed = _random.randf_range(120.0, 230.0)
	streak.length = _random.randf_range(9.0, 20.0)
	streak.width = _random.randf_range(2.0, 3.5)
	return streak


func _draw_streaks() -> void:
	for streak: Streak in _streaks:
		var direction := Vector2.from_angle(streak.angle)
		var start := direction * streak.radius
		var end := direction * maxf(streak.radius - streak.length, 10.0)
		var alpha := clampf((streak.radius - 16.0) / 45.0, 0.0, 0.9)
		draw_line(start, end, Color(1.0, 1.0, 1.0, alpha), streak.width, true)


func _get_hammer_angle() -> float:
	if _phase == Phase.CHARGING:
		return RAISED_ANGLE
	if _phase == Phase.IMPACT:
		return SLAM_ANGLE
	var progress := _windup_elapsed / _windup_duration
	return lerpf(RAISED_ANGLE, SLAM_ANGLE, pow(progress, 3.0))


func _draw_swing_trail() -> void:
	var progress := _windup_elapsed / _windup_duration
	if progress < 0.4:
		return
	var previous_progress := maxf(progress - 0.18, 0.0)
	var previous_angle := lerpf(RAISED_ANGLE, SLAM_ANGLE, pow(previous_progress, 3.0))
	var trail_color := HAMMER_COLOR
	trail_color.a = 0.24
	_draw_hammer(previous_angle, trail_color)


func _draw_hammer(angle_degrees: float, color: Color) -> void:
	var pivot := Vector2(13.0 * _facing_sign, -3.0)
	var angle := deg_to_rad(angle_degrees)
	var axis := Vector2(cos(angle) * _facing_sign, sin(angle))
	var tangent := axis.orthogonal()
	var head_center := pivot + axis * HAMMER_LENGTH
	draw_line(pivot + axis * 5.0, head_center - axis * 8.0, color, 7.0, true)
	var corners := PackedVector2Array([
		head_center - tangent * 17.0 - axis * 9.0,
		head_center + tangent * 17.0 - axis * 9.0,
		head_center + tangent * 17.0 + axis * 9.0,
		head_center - tangent * 17.0 + axis * 9.0,
	])
	draw_colored_polygon(corners, color)


class Streak:
	var angle: float
	var radius: float
	var speed: float
	var length: float
	var width: float
