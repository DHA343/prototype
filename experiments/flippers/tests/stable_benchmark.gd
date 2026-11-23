extends "res://experiments/flippers/tests/stable_audit.gd"


func _run() -> void:
	_config = METHODS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for pass_index: int in 4:
		var methods: Array[Dictionary] = [METHODS[0], METHODS[4], METHODS[8], METHODS[10], METHODS[12]]
		if pass_index % 2 == 1:
			methods.reverse()
		for method: Dictionary in methods:
			_config = method
			for scenario: String in ["empty", "static_enemy", "moving_enemy"]:
				_reset_integration()
				_main.flippers.pass_until_descending = false
				_main.ball.gravity = 0.0
				var actor := _new_enemy(Vector2(960, 500)) as CausalEnemy
				if scenario == "empty":
					actor.collision_layer = 0
				var surface := Vector2(0, 600) if scenario == "moving_enemy" else Vector2.ZERO
				actor.velocity = surface
				actor.trace = {"before": _vec(actor.global_position - surface / 60.0)}
				if method.get("segmented", false):
					actor.trace["raw_matches"] = true
					actor.trace["segments"] = [{"start_time": 0.0, "duration": 1.0 / 60.0,
						"start": actor.trace.before, "velocity": _vec(surface)}]
				await physics_frame
				var samples: Array[int] = []
				var golden_position := Vector2.ZERO
				var golden_velocity := Vector2.ZERO
				var contacts := 0
				for iteration: int in 120:
					actor.current_health = 100.0
					actor._knockback_initial = Vector2.ZERO
					actor._knockback_elapsed = 0.0
					_main.ball.reset_at(Vector2(960, 400), Vector2(0, 3000))
					var begin := Time.get_ticks_usec()
					_main.ball.advance(1.0 / 60.0, [])
					var elapsed := Time.get_ticks_usec() - begin
					var recorder := _main.ball._motion as Recorder
					_check(recorder.discarded_seconds == 0.0, "Benchmark discarded movement time")
					if iteration == 0:
						golden_position = _main.ball.global_position
						golden_velocity = _main.ball.velocity
					if iteration >= 20:
						_check(_main.ball.global_position.distance_to(golden_position) < 0.001,
							"Repeated benchmark position changed")
						_check(_main.ball.velocity.distance_to(golden_velocity) < 0.01,
							"Repeated benchmark velocity changed")
						samples.append(elapsed)
						contacts += recorder.events.size()
				rows.append({"pass": pass_index, "method": method.name, "scenario": scenario, "samples_us": samples,
					"position": _vec(golden_position), "velocity": _vec(golden_velocity),
					"contacts": contacts, "completed_samples": samples.size()})
				actor.free()
	_main.free()
	_write("stable_benchmark.json", {"checks": _checks, "failures": _failures, "cases": rows,
		"scope": "Instrumented ball update only; 20 warmups and 100 measured repetitions; Enemy path capture and rendering excluded"})
	quit(0 if _failures == 0 else 1)
