@tool
extends TableFlipper

enum Rule { CURRENT, WITHOUT_ANGLE, THREE_CONDITIONS }

var rule: Rule = Rule.THREE_CONDITIONS


func is_striking(point: Vector2, normal: Vector2) -> bool:
	if rule == Rule.CURRENT:
		return is_rising() and to_local(point).x > 0.0 and normal.dot(strike_normal()) > 0.5
	return is_rising() and _shot_face(point, global_transform)


func _contact_at(
	center: Vector2, ball_radius: float, pose: Transform2D, omega: float, equalization: float,
) -> Dictionary:
	var hit := super._contact_at(center, ball_radius, pose, omega, equalization)
	if hit.is_empty():
		return hit
	return shot_contact(hit, omega, equalization)


func shot_contact(hit: Dictionary, omega: float, equalization: float) -> Dictionary:
	var pose: Transform2D = hit.pose
	var point: Vector2 = hit.point
	var on_top := _is_upper_contact(point, pose)
	var on_shot_face := on_top and (
		rule == Rule.THREE_CONDITIONS or (pose.affine_inverse() * point).x > 0.0)
	if rule == Rule.CURRENT and on_shot_face:
		var upper := pose.basis_xform(Vector2(0.0, _direction)).normalized()
		on_shot_face = (hit.normal as Vector2).dot(upper) > 0.5
	hit.on_shot_face = on_shot_face
	hit.is_striking = omega * _direction > 0.0 and hit.on_shot_face
	if on_top:
		var arm := point - pose.origin
		var tip_arm := pose * _tip.position - pose.origin
		var amount := equalization if hit.is_striking else 0.0
		hit.strike_surface_velocity = _upper_velocity(_point_velocity(arm, tip_arm, omega, amount), pose)
	return hit


func _shot_face(point: Vector2, pose: Transform2D) -> bool:
	return _is_upper_contact(point, pose) and (
		rule == Rule.THREE_CONDITIONS or (pose.affine_inverse() * point).x > 0.0)
