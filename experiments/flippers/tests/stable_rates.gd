extends "res://experiments/flippers/tests/stable_audit.gd"

var _rate: float = 30.0


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--rate="):
			_rate = float(argument.get_slice("=", 1))
	assert(_rate in [30.0, 120.0], "Rate audit only supports 30 or 120 Hz")
	Engine.physics_ticks_per_second = int(_rate)
	_config = METHODS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	for method: Dictionary in [METHODS[0], METHODS[5], METHODS[9], METHODS[11], METHODS[13]]:
		if "--finish" in OS.get_cmdline_user_args() and not method.get("finish", false):
			continue
		if "--segmented" in OS.get_cmdline_user_args() and not method.get("segmented", false):
			continue
		_config = method
		var rows: Array[Dictionary] = []
		for environment: Dictionary in [ENVIRONMENTS[0], ENVIRONMENTS[10], ENVIRONMENTS[11]]:
			for ordinary: bool in [false, true]:
				if ordinary and environment.name != "full_routes_crowd":
					continue
				for fixture: Vector3 in _fixtures():
					rows.append(await _at_rate(fixture, environment, ordinary))
		_write("stable_rate_" + str(int(_rate)) + "_" + str(method.name) + ".json", {"cases": rows})
		print("Stability rate: ", _rate, ":", method.name, "; cases: ", rows.size())
	_main.free()
	var suffix := "_segmented" if "--segmented" in OS.get_cmdline_user_args() else ""
	if "--finish" in OS.get_cmdline_user_args():
		suffix = "_finish"
	_write("stable_rate_" + str(int(_rate)) + suffix + ".json", {"checks": _checks, "failures": _failures})
	quit(0 if _failures == 0 else 1)


func _at_rate(input: Vector3, environment: Dictionary, ordinary: bool) -> Dictionary:
	_actors.clear()
	_set_rule(2)
	_reset_integration()
	_world(environment.world)
	if ordinary:
		_main.flippers.pass_until_descending = false
		for item: PinballFlipper in _main.flippers.items:
			item.collision_layer = 0
	var points := (_main.flippers.items[0] as TableFlipper).world_polygon_at(
		_main.flippers.items[0].global_transform)
	_main.ball.reset_at(points[0].lerp(points[1], input.x) + Vector2.UP * 28,
		Vector2(0, -1800 if ordinary else 300))
	var primary := _main.ball.global_position + Vector2(input.z, -(54.0 + input.y))
	for index: int in int(environment.enemies):
		var spacing: float = environment.get("spacing", 62.0)
		var offset := Vector2.ZERO if index == 0 else Vector2((-1 if index == 1 else 1) * spacing, 0)
		_actors.append(_new_enemy(primary + offset, environment.get("routes", false)))
	await physics_frame
	var result := _new_result({"ratio": input.x, "gap": input.y, "offset": input.z,
		"rate": _rate, "policy": _config.name, "environment": environment.name, "ordinary": ordinary,
		"initial": _snapshot()})
	for frame: int in int(_rate):
		var plans := _main.flippers.plan_motion(true, true)
		_main.flippers.advance(1.0 / _rate, true, true)
		for index: int in range(_actors.size() - 1, -1, -1):
			if not is_instance_valid(_actors[index]) or not _actors[index].active:
				_actors.remove_at(index)
		for actor: Enemy in _actors:
			actor.prepare(1.0 / _rate)
		if environment.get("crowd", false):
			_main.crowd.calculate(_actors, 1.0 / _rate, _main.boundary.exit_target())
		for actor: Enemy in _actors:
			actor.advance(1.0 / _rate)
		if ordinary:
			plans.clear()
		_main.ball.advance(1.0 / _rate, plans)
		_collect_integration(result, _main.ball._motion as Recorder)
		if result.unresolved:
			break
		if environment.get("routes", false):
			for actor: Enemy in _actors:
				if actor.active and _main.boundary.has_exited(actor.global_position, actor.radius):
					actor.finish(Enemy.ExitReason.ESCAPED)
		await physics_frame
	result["completed"] = not result.unresolved
	result["position"] = _vec(_main.ball.global_position)
	result["velocity"] = _vec(_main.ball.velocity)
	for actor: Enemy in _actors:
		if is_instance_valid(actor):
			actor.free()
	return result
