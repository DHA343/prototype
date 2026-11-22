extends "res://enemies/tests/enemy_test.gd"

var snapshots: Array[Dictionary] = []
var removals: Array[Dictionary] = []


func _run() -> void:
	await super._run()
	var file := FileAccess.open("res://experiments/flippers/evidence/causal_legacy.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"snapshots": snapshots, "removals": removals}))


func _add(point: Vector2) -> Enemy:
	var actor := super._add(point)
	actor.removed.connect(func(enemy: Enemy, reason: Enemy.ExitReason) -> void:
		removals.append({"reason": reason, "position": [enemy.global_position.x, enemy.global_position.y],
			"health": enemy.current_health}))
	return actor


func _check(condition: bool, message: String) -> void:
	if not condition:
		var actors: Array[Dictionary] = []
		for actor: Enemy in _lab.enemies:
			var distance := 0.0
			var point := actor.global_position
			for index: int in range(actor._path_index, actor._path.size()):
				distance += point.distance_to(actor._path[index])
				point = actor._path[index]
			var item := _lab.flippers.items[0] as TableFlipper
			var tangent := (item.tip_position() - item.global_position).normalized()
			var normal := Vector2(tangent.y, -tangent.x)
			var nearest := Geometry2D.get_closest_point_to_segment(actor.global_position,
				item.global_position, item.tip_position())
			var contact := item._contact_at(actor.global_position, actor.radius, item.global_transform, 0.0, 0.0)
			actors.append({"position": [actor.global_position.x, actor.global_position.y],
				"velocity": [actor.velocity.x, actor.velocity.y], "radius": actor.radius,
				"move_speed": actor.move_speed, "path_remaining_px": distance,
				"flipper_depth_px": contact.get("depth", 0.0),
				"signed_test_normal_distance": (actor.global_position - nearest).dot(normal)})
		snapshots.append({"failure": message, "actors": actors,
			"swing_angle": _lab.flippers.swing_angle, "raise_speed": _lab.flippers.raise_speed,
			"ball_position": [_lab.ball.global_position.x, _lab.ball.global_position.y],
			"removals_before": removals.size()})
	super._check(condition, message)
