extends PinballFlippers

var early_exit: bool = false
var sampled_id: int = 0
var initial_contacts: Dictionary = {}
var exit_releases: int = 0


func refresh_target(target: CharacterBody2D, next_velocity_y: float) -> void:
	# Only shorten the existing guard. Descending release is never postponed.
	if early_exit and next_velocity_y <= 1.0 and sampled_id == target.get_instance_id() \
			and is_target_disabled(sampled_id) and initial_contacts.size() == items.size():
		if not initial_contacts.values().has(true):
			exit_releases += 1
			release_target(sampled_id)
	super.refresh_target(target, next_velocity_y)
