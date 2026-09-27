class_name SweepHit
extends ShapeCast2D

signal hurtbox_detected(hurtbox: Hurtbox, hit_direction: Vector2)

var _contact_hurtboxes: Array[Hurtbox] = []


func detect(motion: Vector2) -> void:
	target_position = motion
	force_shapecast_update()

	var current_hurtboxes: Array[Hurtbox] = []
	var impact_position := global_position + motion * get_closest_collision_unsafe_fraction()

	for collision_index in get_collision_count():
		var hurtbox := get_collider(collision_index) as Hurtbox
		if hurtbox == null or hurtbox in current_hurtboxes:
			continue
		current_hurtboxes.append(hurtbox)

		if hurtbox in _contact_hurtboxes:
			continue
		hurtbox_detected.emit(hurtbox, _hit_direction(hurtbox, impact_position, collision_index))

	_contact_hurtboxes = current_hurtboxes


func clear_contacts() -> void:
	_contact_hurtboxes.clear()


func _hit_direction(hurtbox: Hurtbox, impact_position: Vector2, collision_index: int) -> Vector2:
	var direction := (hurtbox.global_position - impact_position).normalized()
	if direction.is_zero_approx():
		return -get_collision_normal(collision_index)
	return direction
