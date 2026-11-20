@tool
class_name PinballBall
extends CharacterBody2D

signal bounced(point: Vector2, normal: Vector2)
signal sound_requested(request: SoundRequest)

const Motion = preload("res://pinball/motion.gd")
const MAX_CONTACTS: int = Motion.MAX_CONTACTS
const CONTACT_MARGIN: float = Motion.CONTACT_MARGIN
const SWEEP_SEPARATION: float = Motion.SEPARATION_MARGIN

@export_range(6.0, 36.0, 1.5, "suffix:px") var radius: float = 15.0:
	set(value):
		radius = value
		_refresh_shape()
@export var color: Color = Color(0.94, 0.95, 0.96):
	set(value):
		color = value 
		queue_redraw()
@export_range(0.0, 4200.0, 30.0, "suffix:px/s²") var gravity: float = 2100.0
@export_range(300.0, 3600.0, 30.0, "suffix:px/s") var max_speed: float = 1950.0

@export_group("Enemy Hit")
@export_range(0.0, 100.0, 1.0) var damage: float = 10.0
## 座標の3倍化で衝突速度も3倍になるため、速度あたりのダメージは1/3にする。
@export_range(0.0, 0.033333, 0.000333) var damage_per_speed: float = 0.005 / 3.0
@export_range(0.0, 3000.0, 30.0, "suffix:px/s") var knockback: float = 300.0
@export_range(0.0, 2.0, 0.05) var knockback_per_speed: float = 0.2
@export var hit_sound: SoundCue

var boundary: PinballBoundary
var flippers: PinballFlippers
var active: bool = true
var last_contact: Vector2 = Vector2.ZERO
var last_normal: Vector2 = Vector2.ZERO
var _enemy_contacts: Array[Enemy] = []
var _motion := Motion.new(self)
var _struck_flippers: Array[PinballFlipper]:
	get:
		return _motion.struck_flippers

@onready var _collision: CollisionShape2D = $CollisionShape2D


static func reflected_velocity(
	incoming: Vector2, normal: Vector2, restitution: float, surface_velocity: Vector2,
) -> Vector2:
	return Motion.reflected_velocity(incoming, normal, restitution, surface_velocity)


func _ready() -> void:
	_motion.native_contact = _resolve_contact
	_motion.swept_contact = _apply_swept_contact
	_motion.separation = _contact_separation
	_motion.contact_recorded = _record_contact
	_refresh_shape()


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)


func reset_at(point: Vector2, initial_velocity: Vector2 = Vector2.ZERO) -> void:
	global_position = point
	velocity = initial_velocity.limit_length(max_speed)
	active = true
	visible = true
	last_normal = Vector2.ZERO
	_enemy_contacts.clear()
	_sync_motion()
	_motion.reset()
	force_update_transform()
	reset_physics_interpolation()


func step_velocity(current_velocity: Vector2, delta: float) -> Vector2:
	_sync_motion()
	return _motion.step_velocity(current_velocity, delta)


func advance(delta: float, swings: Array[PinballFlipper.Swing] = []) -> void:
	if not active:
		return
	_release_enemy_contacts()
	_sync_motion()
	_motion.advance(delta, swings, _advance_motion)


func _advance_motion(delta: float, swings: Array[PinballFlipper.Swing]) -> void:
	_motion.advance_motion(delta, swings)


func _apply_swept_contact(hit: Dictionary) -> void:
	_sync_motion()
	_motion.apply_swept_contact(hit)


func _contact_separation(hit: Dictionary) -> Vector2:
	_sync_motion()
	return _motion.contact_separation(hit)


func _resolve_contact(collision: KinematicCollision2D) -> void:
	var collider := collision.get_collider()
	if collider is PinballFlipper:
		_sync_motion()
		_motion.resolve_contact(collision)
		return
	var normal := collision.get_normal()
	var point := collision.get_position()
	var enemy := collider as Enemy
	var surface_velocity := enemy.velocity if enemy != null else Vector2.ZERO
	var incoming_speed := -(velocity - surface_velocity).dot(normal)
	if incoming_speed <= 0:
		return
	var impact_speed := velocity.length()
	var restitution := enemy.restitution if enemy != null else boundary.restitution_for(collider)
	var bumper := collider as PinballBumper
	if bumper != null:
		var outward_speed := maxf(incoming_speed * restitution, bumper.exit_speed)
		velocity += normal * (incoming_speed + outward_speed)
		if incoming_speed > 30:
			bumper.hit(point)
	else:
		velocity = reflected_velocity(velocity, normal, restitution, surface_velocity)
	if enemy != null and impact_speed > 30 and enemy not in _enemy_contacts:
		_enemy_contacts.append(enemy)
		enemy.receive_hit(damage + impact_speed * damage_per_speed, point,
			-normal * (knockback + impact_speed * knockback_per_speed))
		if hit_sound != null:
			sound_requested.emit(SoundRequest.new(hit_sound, point, self))
	if incoming_speed > 30:
		_record_contact(point, normal)


func _release_enemy_contacts() -> void:
	for index in range(_enemy_contacts.size() - 1, -1, -1):
		var enemy := _enemy_contacts[index]
		if not is_instance_valid(enemy) or not enemy.active \
			or global_position.distance_to(enemy.global_position) > radius + enemy.radius + 1.5:
			_enemy_contacts.remove_at(index)


func _record_contact(point: Vector2, normal: Vector2) -> void:
	last_contact = point
	last_normal = normal
	bounced.emit(point, normal)


func _refresh_shape() -> void:
	queue_redraw()
	if not is_node_ready():
		return
	var shape := CircleShape2D.new()
	shape.radius = radius
	_collision.shape = shape


func _sync_motion() -> void:
	_motion.radius = radius
	_motion.gravity = gravity
	_motion.max_speed = max_speed
	_motion.boundary = boundary
	_motion.flippers = flippers
