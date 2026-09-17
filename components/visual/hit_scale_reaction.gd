class_name HitScaleReaction
extends Node

const MIN_AXIS_SCALE: float = 0.5
const MAX_AXIS_SCALE: float = 1.5

@export_group("Deformation")
@export_range(0.0, 0.5, 0.01) var squash_amount: float = 0.20
@export_range(0.0, 0.5, 0.01) var stretch_amount: float = 0.15
@export_range(0.1, 20.0, 0.1) var response_gain: float = 8.0
@export_range(0.0, 10.0, 0.1) var hit_impulse: float = 3.0

@export_group("Spring", "spring_")
@export_range(1.0, 1000.0, 1.0) var spring_stiffness: float = 200.0
@export_range(0.0, 100.0, 0.1) var spring_damping: float = 10.0
@export_range(0.1, 20.0, 0.1) var spring_max_velocity: float = 8.0

var _spring: ScaleSpring = ScaleSpring.new()
var _base_transform: Transform2D
var _hit_direction: Vector2 = Vector2.RIGHT

@onready var _visual_root: Node2D = $"../VisualRoot"


func _ready() -> void:
	_base_transform = _visual_root.transform
	_spring.settle()
	set_process(false)


func _process(delta: float) -> void:
	_spring.update(delta)

	if _spring.is_settled():
		_spring.settle()
		_reset_visual()
		set_process(false)
		return

	_apply_deformation()


func play(hit_direction: Vector2) -> void:
	var direction := hit_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector2.RIGHT

	_hit_direction = _to_parent_local_direction(direction)
	_spring.stiffness = spring_stiffness
	_spring.damping = spring_damping
	_spring.max_velocity = spring_max_velocity
	_spring.add_impulse(hit_impulse)
	set_process(true)


func _to_parent_local_direction(direction: Vector2) -> Vector2:
	var parent := _visual_root.get_parent() as Node2D
	if parent == null:
		return direction

	var local_direction := parent.global_transform.basis_xform_inv(direction)
	if local_direction.is_zero_approx():
		return Vector2.RIGHT

	return local_direction.normalized()


func _apply_deformation() -> void:
	var reaction := clampf(
		(_spring.value - ScaleSpring.EQUILIBRIUM) * response_gain,
		-1.0,
		1.0
	)
	var squash_scale: float
	var stretch_scale: float
	if reaction >= 0.0:
		squash_scale = 1.0 - squash_amount * reaction
		stretch_scale = 1.0 + stretch_amount * reaction
	else:
		var reverse := -reaction
		squash_scale = 1.0 + stretch_amount * reverse
		stretch_scale = 1.0 - squash_amount * reverse

	squash_scale = clampf(squash_scale, MIN_AXIS_SCALE, MAX_AXIS_SCALE)
	stretch_scale = clampf(stretch_scale, MIN_AXIS_SCALE, MAX_AXIS_SCALE)

	var direction_basis := Transform2D(
		_hit_direction,
		_hit_direction.orthogonal(),
		Vector2.ZERO
	)
	var axis_scale := Transform2D(
		Vector2(squash_scale, 0.0),
		Vector2(0.0, stretch_scale),
		Vector2.ZERO
	)
	var deformation := direction_basis * axis_scale * direction_basis.affine_inverse()
	var base_basis := Transform2D(_base_transform.x, _base_transform.y, Vector2.ZERO)
	var deformed_basis := deformation * base_basis

	_visual_root.transform = Transform2D(
		deformed_basis.x,
		deformed_basis.y,
		_base_transform.origin
	)


func _reset_visual() -> void:
	_visual_root.transform = _base_transform
