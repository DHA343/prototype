@tool
class_name Projectile
extends Node2D

signal impacted(point: Vector2, tint: Color)

enum State {
	STRAIGHT,
	HOMING,
}

const Visuals = preload("res://missiles/visuals.gd")

@export_group("Lifetime")
@export_range(0.1, 20.0, 0.1, "suffix:s") var lifetime: float = 5.0
@export_group("Hit")
@export_range(3.0, 60.0, 0.3, "suffix:px") var hit_radius: float = 18.0
@export_range(0.0, 1000.0, 1.0) var damage: float = 50.0
@export var piercing: bool = false
## 消滅せずに通過できる命中回数。-1は無制限。
@export_range(-1, 12, 1) var penetration_limit: int = -1
@export_group("Appearance")
@export var tint: Color = Color("e99cff")

var state: State = State.STRAIGHT
var active: bool = false

var _visual_seed: float = 0.0
var _target: Enemy
var _velocity: Vector2 = Vector2.ZERO
var _age: float = 0.0

var _contacts: Dictionary[int, bool] = {}
var _remaining_penetrations: int = -1
var _candidates: Array[Enemy] = []

@onready var _visuals: Visuals = $Visuals


func _ready() -> void:
	if active:
		_start_visuals()


func spawn(origin: Vector2, initial_velocity: Vector2, seed_value: float) -> void:
	_begin_flight(origin, initial_velocity, seed_value)
	_start_visuals()


func advance(delta: float, enemies: Array[Enemy] = []) -> void:
	if not active or delta <= 0.0:
		return

	_candidates = enemies
	var previous_position := global_position
	var flight_delta := minf(delta, maxf(0.0, lifetime - _age))
	if flight_delta > 0.0:
		_move(flight_delta)
		_age += flight_delta
		_check_penetration(previous_position, enemies)
	if active and _age >= lifetime:
		_finish_flight(false)
	_candidates = []


func get_target() -> Enemy:
	return _target if is_instance_valid(_target) and _target.active else null


func get_velocity() -> Vector2:
	return _velocity


func get_body_direction() -> Vector2:
	return _velocity.normalized()


func should_emit_exhaust() -> bool:
	return true


func get_guidance_state() -> Dictionary:
	var target := get_target()
	if state != State.HOMING or target == null:
		return {}
	var aim := _get_target_position()
	return {
		"method": "direct",
		"origin": position,
		"target": aim,
		"aim": aim,
		"direction": position.direction_to(aim),
		"velocity": _velocity,
	}


func _begin_flight(origin: Vector2, initial_velocity: Vector2, seed_value: float) -> void:
	position = origin
	state = State.STRAIGHT
	_target = null
	_visual_seed = seed_value
	_velocity = initial_velocity
	_age = 0.0
	_contacts.clear()
	_remaining_penetrations = penetration_limit if piercing else 0
	active = true


func _move(delta: float) -> void:
	position += _velocity * delta


func _get_target_position() -> Vector2:
	if _target.get_parent() == get_parent():
		return _target.position
	var space := get_parent() as Node2D
	return space.to_local(_target.global_position) if space != null else _target.global_position


func _find_target(search_range: float) -> Enemy:
	var closest: Enemy
	var minimum := search_range * search_range
	for enemy: Enemy in _candidates:
		if not enemy.active or enemy.collision_layer == 0 or not _can_hit_enemy(enemy):
			continue
		var distance := global_position.distance_squared_to(enemy.global_position)
		if distance < minimum:
			minimum = distance
			closest = enemy
	return closest


func _check_penetration(previous_position: Vector2, enemies: Array[Enemy]) -> void:
	var candidates := enemies
	if candidates.is_empty() and get_target() != null:
		candidates = [get_target()]
	var hits: Dictionary[Enemy, Vector2] = {}
	var contacts: Dictionary[int, bool] = {}
	for enemy: Enemy in candidates:
		if not enemy.active or enemy.collision_layer == 0:
			continue
		var identity := enemy.get_instance_id()
		var radius_squared := (hit_radius + enemy.radius) ** 2
		if global_position.distance_squared_to(enemy.global_position) <= radius_squared:
			contacts[identity] = true
		if _contacts.has(identity) or not _can_hit_enemy(enemy):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(
			enemy.global_position, previous_position, global_position)
		if closest.distance_squared_to(enemy.global_position) <= radius_squared:
			hits[enemy] = closest
	_contacts = contacts
	if hits.is_empty():
		return

	# 命中で敵一覧が変わるため、判定を終えてからダメージを適用する。
	var applied_hits := 0
	for enemy: Enemy in hits:
		if not is_instance_valid(enemy) or not enemy.active:
			continue
		var point := hits[enemy]
		enemy.receive_hit(damage, point, Vector2.ZERO)
		_visuals.impact(point)
		impacted.emit(point, tint)
		applied_hits += 1
	var should_finish := _remaining_penetrations >= 0 and applied_hits > _remaining_penetrations
	if should_finish:
		_remaining_penetrations = 0
		_finish_flight(false)
		return
	if _remaining_penetrations >= 0:
		_remaining_penetrations -= applied_hits
	for enemy: Enemy in hits:
		if is_instance_valid(enemy):
			_on_penetration(enemy)


func _can_hit_enemy(_enemy: Enemy) -> bool:
	return true


func _on_penetration(_enemy: Enemy) -> void:
	pass


func _start_visuals() -> void:
	if is_instance_valid(_visuals):
		_visuals.follow(
			self, get_velocity, _visual_seed, tint, get_body_direction, should_emit_exhaust,
		)


func _finish_flight(hit: bool) -> void:
	active = false
	if hit:
		impacted.emit(position, tint)
	if is_instance_valid(_visuals):
		_visuals.finish(hit)
	queue_free()
