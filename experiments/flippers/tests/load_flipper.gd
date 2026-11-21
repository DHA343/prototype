@tool
extends TableFlipper

var detection_checks: int = 0
var separation_checks: int = 0
var separation_us: int = 0
var separating: bool = false


func clear_counts() -> void:
	detection_checks = 0
	separation_checks = 0
	separation_us = 0


func _contact_at(
	center: Vector2, radius: float, pose: Transform2D, omega: float, equalization: float,
) -> Dictionary:
	if separating:
		separation_checks += 1
	else:
		detection_checks += 1
	return super._contact_at(center, radius, pose, omega, equalization)


func separation_for(center: Vector2, radius: float, hit: Dictionary, margin: float) -> Vector2:
	separating = true
	var began := Time.get_ticks_usec()
	var offset := super.separation_for(center, radius, hit, margin)
	separation_us += Time.get_ticks_usec() - began
	separating = false
	return offset
