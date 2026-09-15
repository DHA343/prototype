@tool
class_name DropShadow
extends Node2D

@export_group("Shadow")
@export var size: Vector2 = Vector2(42.0, 16.0):
	set(value):
		size = Vector2(maxf(value.x, 0.0), maxf(value.y, 0.0))
		_update_geometry()

@export_range(0.0, 1.0, 0.01) var softness: float = 0.35:
	set(value):
		softness = clampf(value, 0.0, 1.0)
		_update_shader_parameters()

@export var color: Color = Color(0.0, 0.0, 0.0, 0.35):
	set(value):
		color = value
		_update_shader_parameters()

@onready var _shape: MeshInstance2D = $Shape


func _ready() -> void:
	_update_geometry()
	_update_shader_parameters()


func _update_geometry() -> void:
	if not is_instance_valid(_shape) or not _shape.mesh is QuadMesh:
		return

	var quad_mesh := _shape.mesh as QuadMesh
	quad_mesh.size = size


func _update_shader_parameters() -> void:
	if not is_instance_valid(_shape) or _shape.material == null:
		return

	_shape.set_instance_shader_parameter("softness", softness)
	_shape.set_instance_shader_parameter("shadow_color", color)
