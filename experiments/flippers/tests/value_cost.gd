extends "res://experiments/flippers/tests/shot_audit.gd"

const Candidate = preload("res://experiments/flippers/value_candidate.gd")
const Probe = preload("res://experiments/flippers/tests/value_motion.gd")

var _method: String = "A"


func _run() -> void:
	_inputs = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/contact_audit.json")).cases
	var original: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/native_audit.json"))
	for row: Dictionary in original.cases:
		_original[_key(row)] = row
	var extra: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/separation_response.json"))
	var fixtures: Array = original.cases.duplicate()
	fixtures.append_array(extra.cases.filter(func(row: Dictionary) -> bool: return row.has("case")))
	_make_main(false)
	await physics_frame
	await physics_frame
	var all: Array[Dictionary] = []
	for index: int in fixtures.size():
		var saved: Dictionary = fixtures[index]
		for method: String in (["A", "N", "S", "B", "F"] if index % 2 == 0 else ["F", "B", "S", "N", "A"]):
			_method = method
			var plans := _prepare_case(saved, true)
			_main.ball.advance(1.0 / float(saved.rate), plans)
			var probe := _main.ball._motion as Probe
			var expected_position := _main.ball.global_position
			var expected_velocity := _main.ball.velocity
			if method != "F":
				var key: String = {"A": "current", "N": "normal_new_only", "S": "three", "B": "combined"}[method]
				var stored: Dictionary = golden.cases[index].methods[key]
				_check(expected_position.distance_to(_unvec(stored.position)) < .001,
					"Observed impact position differs from prior regression")
				_check(expected_velocity.distance_to(_unvec(stored.velocity)) < .01,
					"Observed impact velocity differs from prior regression")
			var count := probe.events.size()
			var samples: Array[int] = []
			for repeat: int in 4:
				plans = _prepare_case(saved, false)
				var begin := Time.get_ticks_usec()
				_main.ball.advance(1.0 / float(saved.rate), plans)
				var elapsed := Time.get_ticks_usec() - begin
				_check(_main.ball.global_position.distance_to(expected_position) < .001,
					"Lean impact position differs from observer")
				_check(_main.ball.velocity.distance_to(expected_velocity) < .01,
					"Lean impact velocity differs from observer")
				if repeat > 0: samples.append(elapsed)
			all.append({"method": method, "id": saved.id, "suite": saved.suite,
				"rate": saved.rate, "radius": _main.ball.radius, "contacts": count,
				"position": _vec(expected_position), "velocity": _vec(expected_velocity), "samples_us": samples})
		if index % 1000 == 0: print("Impact cost/regression: ", index, "/", fixtures.size())
	_main.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/value_cost.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"cases": all, "scope": "Lean ball update only; setup/reference/probes excluded; one warmup and three timings"}))
	print("Impact cost checks: ", _checks, "; failures: ", _failures)
	quit(0 if _failures == 0 else 1)


func _prepare_case(saved: Dictionary, observed: bool) -> Array[PinballFlipper.Swing]:
	_set_rule(2 if _method in ["S", "B", "F"] else 0)
	var fixture := _fixture(saved)
	var source: PinballFlipper.Swing = fixture.source
	var held: bool = saved.case.angle == 0.0 if saved.has("case") else not _inputs[int(saved.id)].raised
	_main.flippers.pass_until_descending = true
	_main.flippers.advance(fixture.duration, held, held)
	if observed:
		var probe := Probe.new(_main.ball)
		probe.normal_new = _method in ["N", "B", "F"]
		probe.refine = _method == "F"
		probe.audit_detection = false
		probe.native_response = _main.ball._resolve_contact
		probe.contact_recorded = _main.ball._record_contact
		_main.ball._motion = probe
	elif _method in ["N", "B", "F"]:
		var candidate := Candidate.new(_main.ball)
		candidate.refined = _method == "F"
		candidate.native_response = _main.ball._resolve_contact
		candidate.contact_recorded = _main.ball._record_contact
		_main.ball._motion = candidate
	else:
		var motion := PinballMotion.new(_main.ball)
		motion.native_contact = _main.ball._resolve_contact
		motion.contact_recorded = _main.ball._record_contact
		_main.ball._motion = motion
	_main.ball.gravity = 0.0
	_main.ball.collision_mask = (8 << source.flipper.side) if source != null else 8
	_reset_body({"radius": fixture.radius}, fixture.start, fixture.velocity)
	var plans: Array[PinballFlipper.Swing] = []
	if source != null: plans.append(source)
	return plans
