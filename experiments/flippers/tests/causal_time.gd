extends "res://experiments/flippers/tests/causal_audit.gd"


func _attach_recorder(ball: PinballBall) -> void:
	super._attach_recorder(ball)
	(ball._motion as CausalMotion).query_raw_fraction = true


func _run() -> void:
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	_full_events = true
	var rows: Array[Dictionary] = []
	for fixture: Vector3 in [FOCUS[0], FOCUS[1], FOCUS[4]]:
		for config: Dictionary in [TRIALS[0], TRIALS[2]]:
			_config = config
			rows.append(await _scenario(fixture, ENVIRONMENTS[10], false, 2 if fixture != FOCUS[4] else 1))
	_config = TRIALS[0]
	for prefix: Dictionary in [ENVIRONMENTS[9], ENVIRONMENTS[11]]:
		for gap: float in [3, 12]:
			rows.append(await _scenario(Vector3(.05, gap, -36), prefix, true, 2 if gap == 3 else 5, prefix))
	_main.free()
	_write("causal_time.json", {"checks": _checks, "failures": _failures, "cases": rows,
		"scope": "Additional read-only raw PhysicsServer queries from the same pre-query transform. Never applies raw motion or replaces standard collision."})
	print("Causal raw motion checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
