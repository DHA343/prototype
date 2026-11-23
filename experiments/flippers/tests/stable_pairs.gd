extends "res://experiments/flippers/tests/stable_audit.gd"


func _run() -> void:
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/causal_audit.json"))
	_config = METHODS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for source: Dictionary in previous.checkpoints:
		if source.policy != "baseline" or source.environment != "full_reference":
			continue
		for method: Dictionary in [METHODS[0], METHODS[3], METHODS[4], METHODS[6], METHODS[7], METHODS[9]]:
			_config = method
			_reset_integration()
			var state: Dictionary = source.paired_before_intervention
			var frame: int = source.checkpoint
			_main.flippers.advance((10.0 if frame == 1 else 18.0) / 600.0, true, true)
			var plans := _main.flippers.plan_motion(true, true)
			_main.flippers.advance(1.0 / 60.0, true, true)
			_main.ball.reset_at(_unvec(state.ball_position), _unvec(state.ball_velocity))
			if state.guard:
				_main.flippers.disable_target(_main.ball)
			var tick: Dictionary = source.important.back()
			var actors: Array[Enemy] = []
			for index: int in state.enemies.size():
				var saved: Dictionary = state.enemies[index]
				var actor := _new_enemy(_unvec(saved.position)) as CausalEnemy
				actor.velocity = _unvec(saved.velocity)
				actor._movement_velocity = _unvec(saved.move)
				actor._knockback_initial = _unvec(saved.knockback)
				actor._knockback_elapsed = saved.knockback_elapsed
				actor.current_health = saved.health
				actor.trace = tick.enemies[index].duplicate(true)
				actor.force_update_transform()
				actors.append(actor)
			await physics_frame
			var result := _new_result({"policy": method.name, "ratio": source.ratio,
				"gap": source.gap, "offset": source.offset, "initial": _snapshot_for(actors)})
			for update: int in 60:
				if update > 0:
					plans = _main.flippers.plan_motion(true, true)
					_main.flippers.advance(1.0 / 60.0, true, true)
					for actor: Enemy in actors:
						if is_instance_valid(actor) and actor.active:
							actor.prepare(1.0 / 60.0)
							actor.advance(1.0 / 60.0)
				_main.ball.advance(1.0 / 60.0, plans)
				_collect_integration(result, _main.ball._motion as Recorder)
				if update == 0:
					result["first"] = _result(_main.ball._motion as Trace)
				if result.unresolved:
					break
				await physics_frame
			rows.append(result)
			for actor: Enemy in actors:
				if is_instance_valid(actor):
					actor.free()
	_main.free()
	_write("stable_pairs.json", {"checks": _checks, "failures": _failures, "cases": rows})
	quit(0 if _failures == 0 else 1)


func _snapshot_for(actors: Array[Enemy]) -> Dictionary:
	var result := {"position": _vec(_main.ball.global_position), "velocity": _vec(_main.ball.velocity),
		"guard": _main.flippers.is_target_disabled(_main.ball.get_instance_id()), "enemies": []}
	for actor: Enemy in actors:
		result.enemies.append({"position": _vec(actor.global_position), "velocity": _vec(actor.velocity)})
	return result
