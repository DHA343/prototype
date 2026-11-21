@tool
extends TableFlipper

var separating: bool = false
var detection_checks: int = 0
var separation_checks: int = 0


func _contact_at(
	center: Vector2, ball_radius: float, pose: Transform2D, omega: float, equalization: float,
) -> Dictionary:
	if separating:
		separation_checks += 1
	else:
		detection_checks += 1
	return super._contact_at(center, ball_radius, pose, omega, equalization)
