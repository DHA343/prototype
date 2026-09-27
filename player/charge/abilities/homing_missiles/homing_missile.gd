class_name HomingMissile
extends Node2D

signal sound_requested(request: SoundRequest)

var _definition: HomingMissileDefinition
var _direction: Vector2 = Vector2.RIGHT
var _target: Hurtbox
var _departing_target: Hurtbox
var _departure_end_distance: float = 0.0
var _is_departing: bool = false
var _elapsed_time: float = 0.0
var _wobble_time: float = 0.0
var _wobble_phase: float = 0.0

@onready var _hitbox: Hitbox = $Hitbox
@onready var _trail: Trail = $Trail


func _ready() -> void:
	assert(_definition != null, "HomingMissile must be configured before entering the SceneTree.")
	_hitbox.hurtbox_detected.connect(_on_hurtbox_detected)
	_trail.setup(self)


func _physics_process(delta: float) -> void:
	_elapsed_time += delta
	if _elapsed_time >= _definition.flight_duration:
		queue_free()
		return

	_wobble_time += delta
	_update_target()
	_update_direction(delta)
	global_position += _direction * _definition.speed * delta
	rotation = _direction.angle()


func configure(direction: Vector2, definition: HomingMissileDefinition) -> void:
	assert(definition != null, "definition must not be null.")
	assert(not direction.is_zero_approx(), "direction must not be zero.")

	_definition = definition
	_direction = direction.normalized()
	_wobble_phase = randf_range(0.0, TAU)


func _update_target() -> void:
	if _is_departing:
		if not is_instance_valid(_departing_target):
			_is_departing = false
			_departing_target = null
			return

		if global_position.distance_to(_departing_target.global_position) >= _departure_end_distance:
			_target = _departing_target
			_departing_target = null
			_is_departing = false
			return

	if is_instance_valid(_target) or _elapsed_time < _definition.initial_acquisition_delay:
		return

	_target = _find_closest_hurtbox()


func _update_direction(delta: float) -> void:
	var desired_direction := _direction
	if _is_departing and is_instance_valid(_departing_target):
		desired_direction = global_position.direction_to(_departing_target.global_position) * -1.0
	elif is_instance_valid(_target):
		desired_direction = global_position.direction_to(_target.global_position)

	if desired_direction.is_zero_approx():
		return

	var wobble := sin(_wobble_time * _definition.wobble_frequency * TAU + _wobble_phase)
	var desired_angle := desired_direction.angle() + deg_to_rad(_definition.wobble_degrees) * wobble
	var max_turn := deg_to_rad(_definition.turn_speed_degrees) * delta
	_direction = Vector2.from_angle(rotate_toward(_direction.angle(), desired_angle, max_turn))


func _find_closest_hurtbox() -> Hurtbox:
	var closest_hurtbox: Hurtbox
	var closest_distance_squared := INF

	for node in get_tree().get_nodes_in_group(_definition.target_group):
		var enemy := node as Enemy
		if enemy == null or not is_instance_valid(enemy.hurtbox):
			continue

		var hurtbox := enemy.hurtbox
		var distance_squared := global_position.distance_squared_to(hurtbox.global_position)
		if distance_squared < closest_distance_squared:
			closest_hurtbox = hurtbox
			closest_distance_squared = distance_squared

	return closest_hurtbox


func _on_hurtbox_detected(hurtbox: Hurtbox) -> void:
	var hit_direction := global_position.direction_to(hurtbox.global_position)
	if hit_direction.is_zero_approx():
		hit_direction = Vector2.RIGHT
	_apply_hit(hurtbox, hit_direction)

	if _is_departing or hurtbox != _target:
		return

	_departing_target = hurtbox
	_departure_end_distance = global_position.distance_to(hurtbox.global_position) + _definition.departure_distance
	_is_departing = true
	_target = null


func _apply_hit(hurtbox: Hurtbox, hit_direction: Vector2) -> void:
	var hit := HitData.new()
	hit.attacker = self
	hit.damage = _definition.damage
	hit.knockback = _definition.impulse_strength
	hit.hit_direction = hit_direction
	hit.hit_position = hurtbox.global_position
	hurtbox.receive_hit(hit)
	if _definition.hit_cue != null:
		sound_requested.emit(SoundRequest.new(_definition.hit_cue, hurtbox.global_position, self))
