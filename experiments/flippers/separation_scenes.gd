extends RefCounted

const DATA: String = "res://experiments/flippers/evidence/separation_scenes.json"

var cases: Array = []
var actors: Array[Enemy] = []


func _init() -> void:
	cases = JSON.parse_string(FileAccess.get_file_as_string(DATA)).cases


func prepare(main: PinballLab, index: int, variant: int) -> Dictionary:
	actors.clear()
	var input: Dictionary = cases[index].duplicate(true)
	if index == 2 and variant == 1: input.merge(input.deep, true)
	var ball := main.ball
	main.flippers.reset_input()
	main.flippers.swing_angle = 18.0
	main.flippers.raise_speed = 600.0
	main.flippers.return_speed = 420.0
	main.flippers.pass_until_descending = true
	if input.angle > 0:
		main.flippers.advance(input.angle / 600.0, true, true)
	ball.radius = input.radius
	ball.gravity = input.gravity
	ball.max_speed = 3600.0
	ball.collision_mask = 6
	var points := (main.flippers.items[0] as TableFlipper).world_polygon_at(
		main.flippers.items[0].global_transform)
	match str(input.kind):
		"isolated":
			main.boundary.visible = false
			for node: Node in main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
				if not node is PinballFlipper:
					node.collision_layer = 0
					if node is CanvasItem: node.visible = false
			for side: int in 2:
				main.flippers.items[side].collision_layer = 8 << side if side == int(input.side) else 0
				main.flippers.items[side].visible = side == int(input.side)
			ball.collision_mask = 8 << int(input.side)
			ball.reset_at(_vec(input.start), _vec(input.velocity))
		"near", "top":
			var ratio := (.5 if variant == 0 else .7) if input.kind == "near" else .5
			ball.reset_at(points[0].lerp(points[1], ratio) + Vector2.UP * 28, Vector2(0, 300))
			if input.kind == "near":
				_add_enemy(main, ball.global_position + Vector2(0, -90))
		"snapshot":
			var snapshot: Dictionary = input.snapshot
			ball.reset_at(_vec(snapshot.ball_position), _vec(snapshot.ball_velocity))
			if snapshot.guard: main.flippers.disable_target(ball)
			if input.enemies:
				for saved: Dictionary in snapshot.enemies:
					var actor := _add_enemy(main, _vec(saved.position))
					# Restore the known two-tick visual age without advancing its physical state.
					actor.prepare(1.0 / 60.0)
					actor.prepare(1.0 / 60.0)
					actor.velocity = _vec(saved.velocity)
					actor._movement_velocity = _vec(saved.move)
					actor._knockback_initial = _vec(saved.knockback)
					actor._knockback_elapsed = saved.knockback_elapsed
					actor.current_health = saved.health
		"respawn":
			ball.reset_at(_vec(input.start), _vec(input.velocity))
			var actor := _add_enemy(main, _vec(input.enemy_center))
			actor._visual_scale = 1.0
			actor._spring_velocity = 0.0
		_:
			ball.reset_at(_vec(input.start), _vec(input.velocity))
	return input


func advance(main: PinballLab, input: Dictionary, frame: int) -> void:
	var duration: float = 1.0 / input.hz
	var held: bool = input.get("pressed", true)
	var plans := main.flippers.plan_motion(held, held)
	main.flippers.advance(duration, held, held)
	if input.kind == "isolated":
		plans.assign(plans.filter(func(plan: PinballFlipper.Swing) -> bool:
			return plan.flipper.side == int(input.side)))
	# Snapshot enemies are already at the first tick's post-Enemy, pre-ball state.
	if not (input.kind == "snapshot" and frame == 0):
		for actor: Enemy in actors:
			if is_instance_valid(actor) and actor.active:
				actor.prepare(duration)
				actor.advance(duration)
	main.ball.advance(duration, plans)


func snapshot(main: PinballLab) -> Dictionary:
	var enemies: Array[Dictionary] = []
	for actor: Enemy in actors:
		if is_instance_valid(actor):
			enemies.append({"position": _arr(actor.global_position), "velocity": _arr(actor.velocity),
				"move": _arr(actor._movement_velocity), "knockback": _arr(actor._knockback_initial),
				"knockback_elapsed": actor._knockback_elapsed, "health": actor.current_health})
	return {"position": _arr(main.ball.global_position), "velocity": _arr(main.ball.velocity),
		"radius": main.ball.radius, "gravity": main.ball.gravity, "mask": main.ball.collision_mask,
		"angles": main.flippers.items.map(func(item: PinballFlipper) -> float: return item._offset),
		"guard": main.flippers.is_target_disabled(main.ball.get_instance_id()), "enemies": enemies}


func _add_enemy(main: PinballLab, position: Vector2) -> Enemy:
	var actor := load("res://enemies/enemy.tscn").instantiate() as Enemy
	actor.name = "ReplayEnemy"
	actor.position = position
	actor.death_cue = null
	main.get_node("Playfield").add_child(actor)
	actor.prepare(actor.grow_duration)
	actor.force_update_transform()
	actors.append(actor)
	return actor


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])


static func _arr(value: Vector2) -> Array[float]:
	return [value.x, value.y]
