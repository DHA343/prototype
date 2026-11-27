extends Node2D

const SPHERE: Shader = preload("res://tests/ball/sphere.gdshader")

@export_range(2.0, 64.0, 0.5, "suffix:px") var radius: float = 8.0:
	set(value):
		radius = value
		queue_redraw()
@export var finish: ShaderMaterial:
	set(value):
		finish = value
		if is_node_ready():
			_apply_finish()

var _orientation: Quaternion = Quaternion.IDENTITY
var _surface: ShaderMaterial


func _ready() -> void:
	_apply_finish()


func _draw() -> void:
	var extent := Vector2.ONE * radius
	draw_rect(Rect2(-extent, extent * 2.0), Color.WHITE)


func reset_roll() -> void:
	_orientation = Quaternion.IDENTITY
	_update_surface_basis()


## Applies one continuous displacement in world coordinates.
func roll(displacement: Vector2) -> void:
	var distance := displacement.length()
	if is_zero_approx(distance):
		return
	# In camera space +Z faces the viewer and screen +Y points toward 3D -Y.
	var axis := Vector3(displacement.y, displacement.x, 0.0) / distance
	_orientation = (Quaternion(axis, distance / radius) * _orientation).normalized()
	_update_surface_basis()


func _apply_finish() -> void:
	if finish != null:
		_surface = finish.duplicate() as ShaderMaterial
	else:
		_surface = ShaderMaterial.new()
		_surface.shader = SPHERE
	material = _surface
	_update_surface_basis()


func _update_surface_basis() -> void:
	_surface.set_shader_parameter(&"surface_basis", Basis(_orientation).transposed())
