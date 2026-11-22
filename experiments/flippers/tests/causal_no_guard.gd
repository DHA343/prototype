extends "res://experiments/flippers/tests/causal_audit.gd"


func _run() -> void:
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	var matrix := {}
	for original: Dictionary in [ENVIRONMENTS[0], ENVIRONMENTS[1], ENVIRONMENTS[2], ENVIRONMENTS[3],
		ENVIRONMENTS[7], ENVIRONMENTS[9], ENVIRONMENTS[11]]:
		var environment := original.duplicate()
		environment.guard_off = true
		var rows: Array[Dictionary] = []
		for ratio: float in [.05, .15, .30, .50, .70, .90, .99]:
			for gap: float in [3, 12, 36, 72]:
				for offset: float in [-36, 0, 36]:
					rows.append(await _scenario(Vector3(ratio, gap, offset), environment))
		var filename: String = "causal_no_guard_" + str(original.name) + ".json"
		_write(filename, {"cases": rows})
		matrix[original.name] = filename
		print("Causal guard-off control: ", original.name)
	_main.free()
	_write("causal_no_guard.json", {"checks": _checks, "failures": _failures, "matrix": matrix,
		"scope": "Same downward300 initial state, same flippers/Enemy/wall masks and update order as release matrix; only guard disabled."})
	print("Causal guard-off checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
