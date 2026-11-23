extends SceneTree

const Probe = preload("res://experiments/flippers/tests/value_motion.gd")
const Spawner = preload("res://experiments/flippers/tests/value_spawner.gd")
const EnemyProbe = preload("res://experiments/flippers/tests/value_enemy.gd")
const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Candidate = preload("res://experiments/flippers/value_candidate.gd")
const MainProbe = preload("res://experiments/flippers/tests/value_main.gd")

var _main: PinballLab
var _probe: Probe
var _stats: Dictionary
var _seconds: int = 120
var _rate: int = 60
var _seeds: Array[int] = [113, 271, 809]
var _modes: PackedStringArray = ["A", "N", "S", "B", "F"]
var _profiles: PackedStringArray = ["alternate", "held", "adaptive"]
var _observe: bool = true
var _tag: String = ""
var _clock: int = 0
var _caps_run: int = 0
var _slow_run: int = 0
var _jitter_run: int = 0
var _last_delta: Vector2
var _ring: Array = []
var _captures: Array[Dictionary] = []
var _checks: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var value := argument.get_slice("=", 1)
		if argument.begins_with("--seconds="): _seconds = int(value)
		if argument.begins_with("--rate="): _rate = int(value)
		if argument.begins_with("--modes="): _modes = value.split(",")
		if argument.begins_with("--profiles="): _profiles = value.split(",")
		if argument.begins_with("--seeds="):
			_seeds.clear()
			for number: String in value.split(","): _seeds.append(int(number))
		if argument == "--off": _observe = false
		if argument.begins_with("--tag="): _tag = value + "_"
	Engine.physics_ticks_per_second = _rate
	for profile: String in _profiles:
		for episode_seed: int in _seeds:
			for mode: String in _modes:
				var result := await _episode(mode, profile, episode_seed)
				var prefix := "value_" if _observe else "value_off_"
				var filename := prefix + _tag + mode + "_" + profile + "_" + str(episode_seed) + "_" + str(_rate)
				_write(filename + ".json", result)
				print(filename, ": shots=", result.stats.shots, "; caps=", result.stats.caps,
					"; >radius=", result.stats.large_corrections, "; respawns=", result.stats.respawns)
	Input.action_release(&"pinball_left")
	Input.action_release(&"pinball_right")
	quit(0)


func _episode(mode: String, profile: String, episode_seed: int) -> Dictionary:
	seed(episode_seed)
	_main = load("res://main/main.tscn").instantiate() as PinballLab
	var delay := _main.respawn_delay
	_main.set_script(MainProbe)
	_main.respawn_delay = delay
	(_main as MainProbe).inspect_respawn = _observe
	(_main as MainProbe).require_clear_respawn = mode == "P"
	if mode in ["S", "B", "F"]:
		Policy.install(_main, 2)
	var spawner := _main.get_node("EnemySpawner") as EnemySpawner
	var exports := [spawner.enabled, spawner.interval, spawner.enemy_scene,
		spawner.spawn_area, spawner.spawn_parent]
	spawner.set_script(Spawner)
	spawner.enabled = exports[0]
	spawner.interval = exports[1]
	spawner.enemy_scene = exports[2]
	spawner.spawn_area = exports[3]
	spawner.spawn_parent = exports[4]
	(spawner as Spawner).episode_seed = episode_seed
	var template := spawner.enemy_scene.instantiate() as Enemy
	var speed := template.move_speed
	template.set_script(EnemyProbe)
	template.move_speed = speed
	(template as EnemyProbe).inspect_collisions = _observe
	var scene := PackedScene.new()
	assert(scene.pack(template) == OK, "Cannot pack observed Enemy")
	template.free()
	spawner.enemy_scene = scene
	root.add_child(_main)
	_main.set_physics_process(false)
	_main.get_node("Playfield/ShotGuide").set_physics_process(false)
	assert(not _main.is_physics_processing(), "Automatic main update is enabled")
	# Audio playback is outside the physics evaluation; preserve its physical triggers.
	_main.ball.hit_sound = null
	_main.ball.sound_requested.disconnect(_main._sound.request)
	for node: Node in _main.get_node("Playfield").find_children("*", "", true, false):
		if node is PinballBumper: node.hit_sound = null
	_probe = Probe.new(_main.ball)
	_probe.normal_new = mode in ["N", "B", "F"]
	_probe.refine = mode == "F"
	_probe.observe = _observe
	_probe.audit_detection = _observe
	_probe.native_response = _main.ball._resolve_contact
	_probe.contact_recorded = _main.ball._record_contact
	_main.ball._motion = _probe
	if not _observe:
		if mode in ["N", "B", "F"]:
			var candidate := Candidate.new(_main.ball)
			candidate.refined = mode == "F"
			candidate.native_response = _main.ball._resolve_contact
			candidate.contact_recorded = _main.ball._record_contact
			_main.ball._motion = candidate
		else:
			var original := PinballMotion.new(_main.ball)
			original.native_contact = _main.ball._resolve_contact
			original.contact_recorded = _main.ball._record_contact
			_main.ball._motion = original
	_main.launcher._random.seed = episode_seed + 17
	for attempt: int in 300:
		await physics_frame
		if not _main.routes.path_from(Vector2(960, 120), 30).is_empty(): break
	assert(not _main.routes.path_from(Vector2(960, 120), 30).is_empty(), "Navigation not ready")
	_stats = {"ticks": 0, "active_ticks": 0, "contacts": 0, "shots": 0, "caps": 0,
		"max_cap_run": 0, "max_slow_run": 0, "max_jitter_run": 0, "respawns": 0, "drops": 0,
		"spawned": 0, "spawn_skipped": 0, "killed": 0, "escaped": 0, "damage_events": 0,
		"enemy_ticks_removed": 0, "enemy_probes_removed": 0, "enemy_overlaps_removed": 0,
		"enemy_depth_max_px": 0.0, "enemy_count_sum": 0, "enemy_count_max": 0,
		"large_corrections": 0, "corrections_over_one": 0, "correction_max_px": 0.0,
		"new_contact_max_px": 0.0, "release_inside": 0, "release_depth_max_px": 0.0,
		"introduced_events": 0, "path_crossings": 0, "clock_unknown_ticks": 0,
		"physical_missing_ms": 0.0, "cap_physical_missing_ms": 0.0, "legacy_missing_ms": 0.0,
		"detection_opportunities": 0, "detection_disagreements": 0, "raw_queries": 0}
	_stats.merge({"ball_damage_events": 0, "reference_samples": 0, "reference_unstable": 0,
		"coarse_shot_errors": 0, "refined_shot_errors": 0, "missing_ticks": 0,
		"missing_max_ms": 0.0, "missing_over_half_tick": 0})
	_main.spawner.enemy_spawned.connect(_spawned)
	_main.spawner.spawn_skipped.connect(func() -> void: _stats.spawn_skipped += 1)
	_ring.clear()
	_captures.clear()
	_caps_run = 0
	_slow_run = 0
	_jitter_run = 0
	_last_delta = Vector2.ZERO
	var tape_name := "value_inputs_" + _tag + profile + "_" + str(episode_seed) + "_" + str(_rate)
	if profile == "adaptive": tape_name += "_" + mode
	tape_name += ".json"
	var generate_inputs := _observe and (mode == "A" or profile == "adaptive")
	var inputs: Array = []
	if not generate_inputs:
		inputs = JSON.parse_string(FileAccess.get_file_as_string(
			"res://experiments/flippers/evidence/" + tape_name)).inputs
		assert(inputs.size() >= _seconds * _rate, "Input recording is too short")
	var checkpoints: Array[Dictionary] = []
	var samples: Array[int] = []
	var held_until: Array[int] = [0, 0]
	var settings := _settings()
	for frame: int in _seconds * _rate:
		_clock = frame
		var bits: int = _input(profile, episode_seed, frame, held_until) if generate_inputs else inputs[frame]
		if generate_inputs: inputs.append(bits)
		_set_input(&"pinball_left", bits & 1 != 0)
		_set_input(&"pinball_right", bits & 2 != 0)
		var before := _main.ball.global_position
		var active := _main.ball.active
		var begin := Time.get_ticks_usec()
		_main.advance(1.0 / _rate)
		samples.append(Time.get_ticks_usec() - begin)
		_stats.ticks += 1
		_stats.active_ticks += int(active)
		_stats.enemy_count_sum += _main.enemies.size()
		_stats.enemy_count_max = maxi(_stats.enemy_count_max, _main.enemies.size())
		_stats.drops += int(active and not _main.ball.active)
		_stats.respawns += int(not active and _main.ball.active)
		if active and _observe: _observe_tick(before, bits)
		else: _caps_run = 0
		if frame % _rate == 0:
			checkpoints.append({"frame": frame, "position": _vec(_main.ball.global_position),
				"velocity": _vec(_main.ball.velocity), "enemies": _main.enemies.size(),
				"missiles": _main.launcher._flights.size(), "active": _main.ball.active})
		await physics_frame
	for actor: Enemy in _main.enemies: _collect_enemy(actor)
	if _main is MainProbe:
		_stats["occupied_respawns"] = _main.occupied_respawns
		_stats["respawn_overlap_max_px"] = _main.respawn_depth_max
		_stats["blocked_respawn_ticks"] = _main.blocked_ticks
		_stats["max_blocked_respawn_ticks"] = _main.max_blocked_run
	var result := {"mode": mode, "profile": profile, "seed": episode_seed, "rate": _rate,
		"seconds": _seconds, "observed": _observe, "stats": _stats.duplicate(true),
		"settings": settings, "checkpoints": checkpoints, "app_us": samples,
		"reference_policy": "Shared production predicate: diagnostic candidates only; validate independently offline",
		"events": _captures.duplicate(true), "input_file": tape_name}
	if generate_inputs: _write(tape_name, {"inputs": inputs})
	_main.free()
	await physics_frame
	return result


func _observe_tick(before: Vector2, bits: int) -> void:
	_stats.contacts += _probe.events.size()
	_stats.shots += _probe.shots
	_stats.caps += int(_probe.cap)
	_stats.raw_queries += _probe.raw_queries
	_stats.detection_opportunities += _probe.detection_checks
	_stats.detection_disagreements += _probe.detection_differences.size()
	_stats.legacy_missing_ms += _probe.discarded_legacy_s * 1000
	if _observe:
		if _probe.discarded_true_s < 0: _stats.clock_unknown_ticks += 1
		else:
			_stats.physical_missing_ms += _probe.discarded_true_s * 1000
			if _probe.cap: _stats.cap_physical_missing_ms += _probe.discarded_true_s * 1000
			_stats.missing_ticks += int(_probe.discarded_true_s > .000001)
			_stats.missing_max_ms = maxf(_stats.missing_max_ms, _probe.discarded_true_s * 1000)
			_stats.missing_over_half_tick += int(_probe.discarded_true_s > .5 / _rate)
	var reference_error := false
	for reference: Dictionary in _probe.references:
		_stats.reference_samples += 1
		_stats.reference_unstable += int(not reference.stable)
		if reference.stable:
			_stats.coarse_shot_errors += int(reference.shot != reference.coarse_shot)
			_stats.refined_shot_errors += int(reference.shot != reference.refined_shot)
			reference_error = reference_error or reference.shot != reference.coarse_shot
	_stats.release_inside += int(not _probe.released_inside.is_empty())
	for release: Dictionary in _probe.released_inside:
		_stats.release_depth_max_px = maxf(_stats.release_depth_max_px, release.depth_px)
	var large := false
	var environmental := false
	for event: Dictionary in _probe.events:
		if event.is_empty(): continue
		_stats.ball_damage_events += int(event.get("ball_damage", 0.0) > 0.0)
		var correction: float = event.correction_px
		_stats.correction_max_px = maxf(_stats.correction_max_px, correction)
		_stats.corrections_over_one += int(correction > 1.0)
		_stats.large_corrections += int(correction > _main.ball.radius)
		if event.new_contact:
			_stats.new_contact_max_px = maxf(_stats.new_contact_max_px, correction)
		large = large or correction > _main.ball.radius
		if event.has("environment"):
			_stats.introduced_events += int(not event.environment.introduced.is_empty())
			_stats.path_crossings += int(event.environment.path_only)
			environmental = environmental or not event.environment.introduced.is_empty() \
				or event.environment.path_only
	var movement := _main.ball.global_position - before
	_caps_run = _caps_run + 1 if _probe.cap else 0
	_slow_run = _slow_run + 1 if movement.length() <= .03 and _main.ball.velocity.length() > 30 \
		and not _probe.events.is_empty() else 0
	_jitter_run = _jitter_run + 1 if movement.dot(_last_delta) < 0 and movement.length() > .03 \
		and not _probe.events.is_empty() else 0
	_last_delta = movement
	_stats.max_cap_run = maxi(_stats.max_cap_run, _caps_run)
	_stats.max_slow_run = maxi(_stats.max_slow_run, _slow_run)
	_stats.max_jitter_run = maxi(_stats.max_jitter_run, _jitter_run)
	var row := [_clock, bits, _main.ball.global_position.x, _main.ball.global_position.y,
		_main.ball.velocity.x, _main.ball.velocity.y, _main.ball.active, _probe.cap, _main.enemies.size()]
	for capture: Dictionary in _captures:
		if _clock > capture.frame and _clock <= capture.frame + _rate:
			capture.tail.append(row)
	if _observe and (large or environmental or _probe.cap or _probe.discarded_true_s > .000001 \
			or reference_error or not _probe.detection_differences.is_empty()) and _captures.size() < 32:
		_captures.append({"frame": _clock, "events": _probe.events.duplicate(true),
			"release": _probe.released_inside.duplicate(true), "before": _ring.duplicate(true),
			"tail": [row], "true_missing_ms": _probe.discarded_true_s * 1000,
			"disagreements": _probe.detection_differences.duplicate(true),
			"references": _probe.references.duplicate(true)})
	_ring.append(row)
	if _ring.size() > _rate: _ring.pop_front()


func _input(profile: String, episode_seed: int, frame: int, held_until: Array[int]) -> int:
	var time := float(frame) / _rate
	var phase := fmod(float(episode_seed) * .013, .5)
	if profile == "alternate":
		return int(fmod(time + phase, .55) < .12) + 2 * int(fmod(time + phase + .275, .55) < .12)
	if profile == "held": return 3 if fmod(time + phase, 1.2) < .8 else 0
	if frame % maxi(1, _rate / 10) == 0 and _main.ball.active and _main.ball.velocity.y > 0:
		for item: TableFlipper in _main.flippers.items:
			var center := _main.ball.global_position
			var points := item.world_polygon_at(item.global_transform)
			if center.x >= item.fixed_left - _main.ball.radius and center.x <= item.fixed_right + _main.ball.radius \
				and center.y > minf(points[0].y, points[1].y) - _main.ball.radius - _main.ball.velocity.y * .12:
				held_until[item.side] = frame + maxi(1, int(.15 * _rate))
	return int(frame < held_until[0]) + 2 * int(frame < held_until[1])


func _spawned(actor: Enemy) -> void:
	_stats.spawned += 1
	actor.death_cue = null
	actor.removed.connect(func(enemy: Enemy, reason: Enemy.ExitReason) -> void:
		_stats["killed" if reason == Enemy.ExitReason.KILLED else "escaped"] += 1
		_collect_enemy(enemy))
	actor.damaged.connect(func(_amount: float, _point: Vector2, _impulse: Vector2) -> void:
		_stats.damage_events += 1)


func _collect_enemy(actor: Enemy) -> void:
	if actor is EnemyProbe:
		_stats.enemy_ticks_removed += actor.step_count
		_stats.enemy_probes_removed += actor.probe_count
		_stats.enemy_overlaps_removed += actor.overlap_count
		_stats.enemy_depth_max_px = maxf(_stats.enemy_depth_max_px, actor.max_depth)


func _settings() -> Dictionary:
	return {"radius": _main.ball.radius, "gravity": _main.ball.gravity, "max_speed": _main.ball.max_speed,
		"damage": _main.ball.damage, "respawn_delay": _main.respawn_delay,
		"spawn_interval": _main.spawner.interval, "spawn_enabled": _main.spawner.enabled,
		"raise_speed": _main.flippers.raise_speed, "swing_angle": _main.flippers.swing_angle,
		"pass_until_descending": _main.flippers.pass_until_descending,
		"missiles_enabled": is_instance_valid(_main.launcher)}


func _set_input(action: StringName, pressed: bool) -> void:
	if pressed: Input.action_press(action)
	else: Input.action_release(action)


func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open("res://experiments/flippers/evidence/" + name, FileAccess.WRITE)
	assert(file != null, "Cannot write impact evidence")
	file.store_string(JSON.stringify(value))


func _vec(value: Vector2) -> Array[float]:
	return [value.x, value.y]
