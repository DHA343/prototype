@tool
class_name ChromaticAberration
extends PostProcessEffect

enum Direction {
	HORIZONTAL,
	VERTICAL,
	RADIAL,
}

const EFFECT_SHADER: Shader = preload("./chromatic_aberration.gdshader")

@export var direction: Direction = Direction.HORIZONTAL:
	set(value):
		if direction == value:
			return

		direction = value
		notify_change()

@export_range(0.0, 32.0, 0.5) var amount: float = 2.0:
	set(value):
		if is_equal_approx(amount, value):
			return

		amount = value
		notify_change()


func _get_shader() -> Shader:
	return EFFECT_SHADER


func _update_shader_parameters() -> void:
	shader_parameters[&"direction"] = direction
	shader_parameters[&"amount"] = amount
