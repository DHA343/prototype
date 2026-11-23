extends "res://experiments/flippers/tests/shot_audit.gd"

const Probe = preload("res://experiments/flippers/tests/value_motion.gd")
const Independent = preload("res://experiments/flippers/tests/value_reference.gd")


func _run() -> void:
	_make_main(false)
	await physics_frame
	await physics_frame
	var rows: Array[Dictionary] = []
	for fixture: Dictionary in [
		{"name": "N_held_809_tick503", "start": Vector2(941.134521484375, 1035.06750488281),
			"velocity": Vector2(-733.067626953125, 277.265533447266)},
		{"name": "A_held_809_tick2447", "start": Vector2(609.556884765625, 968.388977050781),
			"velocity": Vector2(187.136245727539, 57.3929824829102)},
	]:
		for rule: int in [0, 2]:
			_set_rule(rule)
			_set_pose(0.0)
			_main.ball.collision_mask = 2 | 4 | 8 | 16
			_main.ball.radius = 24.0
			_main.ball.reset_at(fixture.start, fixture.velocity)
			var plans := _main.flippers.plan_motion(true, true)
			_main.flippers.advance(1.0 / 60.0, true, true)
			for plan: PinballFlipper.Swing in plans:
				_main.ball.add_collision_exception_with(plan.flipper)
			var native := _main.ball.move_and_collide(fixture.velocity / 60.0, true, .03, true)
			var limit := 1.0 / 60.0
			if native != null:
				limit *= clampf(native.get_travel().dot(fixture.velocity / 60.0) /
					(fixture.velocity as Vector2).length_squared() * 3600.0, 0, 1)
			for plan: PinballFlipper.Swing in plans:
				_main.ball.remove_collision_exception_with(plan.flipper)
			var probe := Probe.new(_main.ball)
			probe.flippers = _main.flippers
			probe.radius = 24.0
			var reference := probe._reference(plans, fixture.velocity, limit, 16384)
			var check := probe._reference(plans, fixture.velocity, limit, 8192)
			_check(reference.found == check.found and absf(reference.time - check.time) < .00001,
				"Focused reference is unstable")
			var methods := {}
			for refine: bool in [false, true]:
				var sources := RefinedMotion.plans_for(plans, 4) if refine else plans
				var hit := _main.flippers.first_contact(sources, fixture.start,
					fixture.velocity, 24.0, 0.0, limit)
				methods["B+4" if refine else "B"] = _describe(hit, fixture.velocity)
			var oracle_hit := {}
			for plan: PinballFlipper.Swing in plans:
				var time: float = reference.time
				var pose := plan.parent_pose * Transform2D(
					plan.start_angle + plan.speed * minf(time, plan.stop_time), plan.flipper.position)
				var hit := plan.flipper._contact_at(fixture.start + fixture.velocity * time,
					24.0005, pose, plan.speed if time < plan.stop_time else 0.0,
					_main.flippers.power_equalization)
				if hit.is_empty(): continue
				hit.time = time
				hit.flipper = plan.flipper
				hit.center = fixture.start + fixture.velocity * time
				hit.polygon = (plan.flipper as TableFlipper).world_polygon_at(pose)
				oracle_hit = hit
			methods.shared_predicate_reference = _describe(oracle_hit, fixture.velocity)
			var independent := Independent.first_contact(plans, fixture.start,
				fixture.velocity, 24.0, limit, _main.flippers.power_equalization, 16384)
			var independent_check := Independent.first_contact(plans, fixture.start,
				fixture.velocity, 24.0, limit, _main.flippers.power_equalization, 8192)
			_check(independent.is_empty() == independent_check.is_empty(),
				"Independent reference presence differs between densities")
			if not independent.is_empty():
				_check(absf(independent.time - independent_check.time) < .00001,
					"Independent reference contact time is unstable")
			methods.reference = _describe(independent, fixture.velocity)
			rows.append({"fixture": fixture.name, "rule": rule, "limit_ms": limit * 1000,
				"native_target": str(native.get_collider().name) if native != null else "none",
				"methods": methods})
	_main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/value_focus.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures, "cases": rows}))
	print("Focused contact checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _describe(hit: Dictionary, incoming: Vector2) -> Dictionary:
	if hit.is_empty(): return {"found": false, "shot": false}
	var shot: bool = hit.is_striking and (incoming - hit.surface_velocity).dot(hit.normal) < 0.0
	var velocity := PinballMotion.reflected_velocity(incoming, hit.normal,
		_main.flippers.restitution, hit.strike_surface_velocity if shot else hit.surface_velocity)
	if shot:
		velocity = _main.flippers.direct_shot(velocity, hit.ratio, hit.flipper.side, hit.normal)
	var result := {"found": true, "shot": shot, "time_ms": hit.time * 1000,
		"depth": hit.depth, "velocity": _vec(velocity.limit_length(3600)),
		"point": _vec(hit.point), "normal": _vec(hit.normal)}
	if hit.has("center"):
		result.center = _vec(hit.center)
		result.polygon = Array(hit.polygon).map(func(point: Vector2) -> Array: return _vec(point))
	return result
