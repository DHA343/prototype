class_name PunchAttack
extends Node2D

var damage: float
var knockback: float
var hit_active_duration: float
var hit_camera_shake: OneShotCameraShakeCue
var hit_sound: SoundCue
var side_offset: float
var hitbox_forward_offset: float
var hitbox_radius: float
var hitbox_height: float
var visual_start_distance: float
var visual_end_distance: float
var move_duration: float
var fade_duration: float

var _attacker: Node = null
var _feedback: Feedback
var _direction: Vector2 = Vector2.RIGHT
var _side_sign: float = -1.0
var _hit_hurtbox_ids: Dictionary[int, bool] = {}
var _has_requested_hit_camera_shake: bool = false

@onready var _visual_root: Node2D = $VisualRoot
@onready var _hitbox: Hitbox = $Hitbox
@onready var _collision_shape: CollisionShape2D = $Hitbox/CollisionShape2D


func _ready() -> void:
	var capsule_shape := _collision_shape.shape.duplicate() as CapsuleShape2D
	assert(capsule_shape != null, "Punch hitbox must use a CapsuleShape2D.")
	_collision_shape.shape = capsule_shape
	_hitbox.hurtbox_detected.connect(_on_hurtbox_detected)
	_hitbox.monitoring = false


## Call once after adding the attack to its scene parent.
func launch(
	attacker: Node,
	direction: Vector2,
	side_sign: float,
	feedback: Feedback
) -> void:
	assert(feedback != null, "A scene feedback service is required.")
	_attacker = attacker
	_feedback = feedback
	_direction = direction.normalized()
	if _direction.is_zero_approx():
		_direction = Vector2.RIGHT
	_side_sign = -1.0 if side_sign < 0.0 else 1.0

	global_rotation = _direction.angle()
	var capsule_shape := _collision_shape.shape as CapsuleShape2D
	capsule_shape.radius = hitbox_radius
	capsule_shape.height = hitbox_height
	_collision_shape.position = Vector2(hitbox_forward_offset, side_offset * _side_sign)
	_collision_shape.rotation = PI * 0.5
	_hitbox.monitoring = true

	_play_visual()
	get_tree().create_timer(hit_active_duration).timeout.connect(_disable_hitbox)
	get_tree().create_timer(maxf(hit_active_duration, move_duration)).timeout.connect(queue_free)


func _on_hurtbox_detected(hurtbox: Hurtbox) -> void:
	var hurtbox_id := hurtbox.get_instance_id()
	if _hit_hurtbox_ids.has(hurtbox_id):
		return

	_hit_hurtbox_ids[hurtbox_id] = true
	var hit := HitData.new()
	hit.attacker = _attacker
	hit.damage = damage
	hit.knockback = knockback
	hit.hit_position = hurtbox.global_position
	hit.hit_direction = _direction
	hurtbox.receive_hit(hit)
	_request_hit_sound(hit.hit_position)
	_request_hit_camera_shake()


func _request_hit_camera_shake() -> void:
	if _has_requested_hit_camera_shake:
		return
	_has_requested_hit_camera_shake = true
	if hit_camera_shake == null:
		return

	_feedback.camera_shake_requested.emit(CameraShakeRequest.play(hit_camera_shake, _direction))


func _request_hit_sound(hit_position: Vector2) -> void:
	if hit_sound == null:
		return
	var sound_request := SoundRequest.new(hit_sound, hit_position, self)
	_feedback.sound_requested.emit(sound_request)


func _play_visual() -> void:
	var start_position := Vector2(visual_start_distance, side_offset * _side_sign)
	var end_position := Vector2(visual_end_distance, side_offset * _side_sign)
	_visual_root.position = start_position

	var move_tween := create_tween()
	move_tween.tween_property(
		_visual_root,
		"position",
		end_position,
		move_duration
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	var fade_tween := create_tween()
	fade_tween.tween_interval(maxf(move_duration - fade_duration, 0.0))
	fade_tween.tween_property(_visual_root, "modulate:a", 0.0, fade_duration)


func _disable_hitbox() -> void:
	_hitbox.monitoring = false
