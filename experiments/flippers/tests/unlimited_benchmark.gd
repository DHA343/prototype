extends "res://experiments/flippers/tests/unlimited_audit.gd"

const LeanRelease = preload("res://experiments/flippers/release_motion.gd")


func _attach_recorder(ball: PinballBall) -> void:
	var candidate := LeanRelease.new(ball)
	candidate.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	candidate.recovery.limit = _config.limit
	candidate.recovery.distance_limited = not _config.get("unlimited", false)
	candidate.recovery.diagnostics = false
	candidate.native_response = ball._resolve_contact
	candidate.contact_recorded = ball._record_contact
	ball._motion = candidate


func _run() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/unlimited_audit.json"))
	var pair: Array[int] = []
	var common: Array[int] = []
	for index: int in 84:
		var a: Dictionary = golden.integration.baseline.near_enemy[index]
		var b: Dictionary = golden.integration.unlimited.near_enemy[index]
		var c: Dictionary = golden.integration.safe12.near_enemy[index]
		if a.completed and b.completed and a.exhausted_updates == 0 and b.exhausted_updates == 0:
			pair.append(index)
			if c.completed and c.exhausted_updates == 0:
				common.append(index)
	var hashes := _production_hashes()
	_config = TRIALS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rounds: Array[Dictionary] = []
	var validation: Array[Dictionary] = []
	var debug_only := OS.get_cmdline_user_args().has("--verify")
	for round_index: int in (1 if debug_only else 8):
		var methods := {}
		for offset: int in 3:
			var config: Dictionary = TRIALS[(offset + round_index) % 3]
			_config = config
			_set_rule(2)
			var rows: Array[Dictionary] = []
			var selected: Array[int] = common if config.name == "safe12" else pair
			for index: int in selected:
				var expected: Dictionary = golden.integration[config.name].near_enemy[index]
				_reset_integration()
				var points := ( _main.flippers.items[0] as TableFlipper).world_polygon_at(
					_main.flippers.items[0].global_transform)
				_main.ball.reset_at(points[0].lerp(points[1], expected.ratio) + Vector2.UP * 28, Vector2(0, 300))
				var enemy := load("res://enemies/enemy.tscn").instantiate() as Enemy
				enemy.death_cue = null
				enemy.position = _main.ball.global_position + Vector2(expected.offset, -(54.0 + expected.gap))
				_main.get_node("Playfield").add_child(enemy)
				enemy.prepare(enemy.grow_duration)
				await physics_frame
				var times: Array[int] = []
				var first_difference := {}
				for frame: int in 60:
					var plans := _main.flippers.plan_motion(true, true)
					_main.flippers.advance(1.0 / 60.0, true, true)
					if is_instance_valid(enemy):
						enemy.prepare(1.0 / 60.0)
						enemy.advance(1.0 / 60.0)
					var began := Time.get_ticks_usec()
					_main.ball.advance(1.0 / 60.0, plans)
					times.append(Time.get_ticks_usec() - began)
					if round_index == 0 and first_difference.is_empty():
						var reference: Dictionary = expected.trajectory[frame]
						if _main.ball.global_position.distance_to(_unvec(reference.position)) > 0.001:
							first_difference = {"frame": frame, "position": _vec(_main.ball.global_position),
								"velocity": _vec(_main.ball.velocity), "reference": reference,
								"release": (_motion as LeanRelease).recovery.tick.duplicate(true)}
					_check(not (_motion as LeanRelease).recovery.failed, "CPU cohort failed during replay")
					await physics_frame
				if round_index == 0:
					if not first_difference.is_empty():
						validation.append({"mode": config.name, "index": index, "first_difference": first_difference,
							"position_error_px": _main.ball.global_position.distance_to(_unvec(expected.position)),
							"velocity_error_px_s": _main.ball.velocity.distance_to(_unvec(expected.trajectory[-1].velocity))})
					_check(_main.ball.global_position.distance_to(_unvec(expected.position)) < 0.001,
						"Lean integration position differs")
					_check(_main.ball.velocity.distance_to(_unvec(expected.trajectory[-1].velocity)) < 0.01,
						"Lean integration velocity differs")
					_check(_main.ball.get_collision_exceptions().is_empty(), "Lean exclusions leaked")
				rows.append({"index": index, "times_us": times})
				if is_instance_valid(enemy):
					enemy.free()
			methods[config.name] = rows
		rounds.append({"warmup": round_index == 0, "methods": methods})
		print("Unlimited CPU round: ", round_index + 1, "/8")
	for path: String in hashes:
		_check(FileAccess.get_sha256("res://" + path) == hashes[path], "Production file changed")
	_main.free()
	_write("unlimited_benchmark.json", {"checks": _checks, "failures": _failures,
		"performance_valid": _failures == 0 and not debug_only,
		"validation_differences": validation,
		"common_indices": common, "pair_indices": pair, "rounds": rounds,
		"production_sha256": hashes,
		"scope": "Same initial near-enemy inputs, full sixty updates, completed without caps. Body advance only; no traces or observation. Seven measured rounds after warmup; rotated order."})
	print("Unlimited CPU checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)
