extends "res://experiments/flippers/release.gd"

var stages: Array[Dictionary] = []


func begin(
	target: CharacterBody2D, size: float, manager: PinballFlippers,
	plans: Array[PinballFlipper.Swing], duration: float,
) -> void:
	stages.clear()
	super.begin(target, size, manager, plans, duration)


func refresh(next_velocity_y: float) -> void:
	var eligible := flippers.is_target_disabled(body.get_instance_id()) and next_velocity_y > 1.0
	if eligible:
		stages.append({"stage": "1_release_request", "position": [body.global_position.x, body.global_position.y],
			"velocity": [body.velocity.x, body.velocity.y], "next_velocity_y": next_velocity_y,
			"guard": true, "time_ms": 0.0, "remaining_ms": _duration * 1000.0})
	super.refresh(next_velocity_y)
	if eligible:
		stages.append({"stage": "2_release_result", "position": [body.global_position.x, body.global_position.y],
			"velocity": [body.velocity.x, body.velocity.y],
			"guard": flippers.is_target_disabled(body.get_instance_id()), "failed": failed,
			"correction": tick.correction, "time_ms": 0.0, "remaining_ms": _duration * 1000.0})
