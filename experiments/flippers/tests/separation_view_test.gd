extends SceneTree

const Preview = preload("res://experiments/flippers/separation_preview.gd")
const Lean = preload("res://experiments/flippers/separation.gd")

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var preview := load("res://experiments/flippers/separation_preview.tscn").instantiate() as Preview
	root.add_child(preview)
	while preview.loading: await physics_frame
	var rows: Array[Dictionary] = []
	for index: int in 8:
		for variant: int in ([0, 1] if index in [2, 3] else [0]):
			var paired := []
			for mode: int in 2:
				preview.variant = variant
				await preview.reset_case(index, mode)
				paired.append(preview.initial.duplicate(true))
				_check(not preview.main.is_physics_processing(), "Main updates independently")
				_check(not preview.main.spawner.enabled, "Automatic spawner is enabled")
				for frame: int in int(preview.input.hz) * 3:
					preview.step_once()
					await physics_frame
				var first: Dictionary = preview.events[0] if not preview.events.is_empty() else {}
				_check(not first.is_empty(), "Scenario has no contact")
				var observed := {"scene": index + 1, "variant": variant, "mode": "S" if mode == 0 else "B",
					"initial": preview.initial.duplicate(true), "updates": preview.frames,
					"max_correction_px": preview.max_correction, "caps": preview.capped_updates,
					"drop": preview.dropped, "end": _vec(preview.main.ball.global_position),
					"events": preview.events.duplicate(true), "fidelity": preview.input.fidelity}
				rows.append(observed)
				if preview.input.has("expected"):
					_check(absf(preview.events[0].correction_px - preview.input.expected[observed.mode]) < .003,
						"Saved first-update correction differs")
				if index == 0:
					_check(first.new_contact and first.target == "RightFlipper", "Right-side sample changed")
					_check(absf(first.correction_px - (93.410484 if mode == 0 else .287146)) < .003,
						"Recorded right-side correction differs")
				if index in [4, 5]:
					_check(absf(first.correction_px - 60.60965) < .003, "Release-side sample changed")
					_check(not first.new_contact, "Initial release treated as new contact")
				if index == 5:
					_check(not first.environment.introduced.is_empty(), "Enemy interference did not reproduce")
				if index == 6:
					_check(first.kind == "native" and first.correction_px > 1, "Respawn approximation has no recovery")
				if index == 7:
					_check(first.shot, "Top control is not a shot")
				print("Scene ", index + 1, "/", variant, " ", observed.mode,
					": first=", first.get("correction_px", 0), "; caps=", preview.capped_updates)
			_check(paired[0] == paired[1], "S/B initial conditions differ")
	# Same state, one update: the recorder must not change the existing response.
	for index: int in 8:
		for mode: int in 2:
			preview.variant = 0
			await preview.reset_case(index, mode)
			preview.step_once()
			var position := preview.main.ball.global_position
			var velocity := preview.main.ball.velocity
			await preview.reset_case(index, mode)
			var original: PinballMotion = Lean.new(preview.main.ball) if mode == 1 else PinballMotion.new(preview.main.ball)
			if mode == 1: (original as Lean).native_response = preview.main.ball._resolve_contact
			else:
				original.separate_new_contacts = false
				original.native_contact = preview.main.ball._resolve_contact
			original.contact_recorded = preview.main.ball._record_contact
			preview.main.ball._motion = original
			preview.scenes.advance(preview.main, preview.input, 0)
			_check(preview.main.ball.global_position.distance_to(position) < .001, "Observer changed first update position")
			_check(preview.main.ball.velocity.distance_to(velocity) < .01, "Observer changed first update velocity")
	# Slow playback consumes fewer updates, not a smaller physics delta or interpolated correction.
	await preview.reset_case(0, 1)
	preview.step_once()
	var expected := preview.main.ball.global_position
	await preview.reset_case(0, 1)
	preview.speed = .125
	preview.playing = true
	for frame: int in 7: preview._physics_process(1.0 / 60.0)
	_check(preview.frames == 0, "Slow replay advances too early")
	preview._physics_process(1.0 / 60.0)
	preview.playing = false
	_check(preview.frames == 1, "Slow replay does not advance one fixed update")
	_check(preview.main.ball.global_position.distance_to(expected) < .001, "Slow playback changed physics")
	_check(Engine.time_scale == 1.0, "Playback changes the global time scale")
	preview.free()
	var file := FileAccess.open("res://experiments/flippers/evidence/separation_view.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": _checks, "failures": _failures,
		"cases": rows, "scope": "Eight visual scenes, both S/B, saved fixtures and observer/lean checks"}))
	print("Visual comparison checks: ", _checks, "; failures: ", _failures.size())
	quit(0 if _failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		push_error(message)


static func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]
