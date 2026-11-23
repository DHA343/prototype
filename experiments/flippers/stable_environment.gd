extends "res://experiments/flippers/tests/separation_environment.gd"

const EnemyPath = preload("res://experiments/flippers/enemy_path.gd")

var paths: Array[Dictionary] = []


func observe(
	body: CharacterBody2D, radius: float, ignored: PhysicsBody2D,
	start: Vector2, offset: Vector2, flippers: PinballFlippers,
	plans: Array[PinballFlipper.Swing], time: float,
) -> Dictionary:
	var result := super.observe(body, radius, ignored, start, offset, flippers, plans, time)
	for path: Dictionary in paths:
		var enemy: Enemy = path.body
		if not is_instance_valid(enemy) or not enemy.active or enemy == ignored:
			continue
		var center := EnemyPath.position_at(path, time)
		var reach := radius + enemy.radius
		var actor := {"id": str(enemy.get_instance_id()), "name": str(enemy.name), "kind": "enemy"}
		if start.distance_to(center) < reach:
			result.before.append(actor)
		if (start + offset).distance_to(center) < reach:
			result.after.append(actor)
		if Geometry2D.get_closest_point_to_segment(center, start, start + offset).distance_to(center) < reach:
			result.path_blocked = true
	var ids: Array = result.before.map(func(actor: Dictionary) -> String: return actor.id)
	result.introduced = result.after.filter(func(actor: Dictionary) -> bool: return not ids.has(actor.id))
	result.path_only = result.path_blocked and result.before.is_empty() and result.after.is_empty()
	return result
