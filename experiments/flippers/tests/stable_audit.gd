extends "res://experiments/flippers/tests/causal_audit.gd"

const Stable = preload("res://experiments/flippers/stable_motion.gd")
const SafeRelease = preload("res://experiments/flippers/stable_release.gd")
const TrackedEnemy = preload("res://experiments/flippers/tests/stable_enemy.gd")
const METHODS: Array[Dictionary] = [
	{"name": "baseline", "policy": 0, "limit": 12.0, "separation": true},
	{"name": "state", "policy": 0, "limit": 12.0, "stable": true, "clock": false},
	{"name": "clock", "policy": 0, "limit": 12.0, "stable": true, "state": false},
	{"name": "state_clock", "policy": 0, "limit": 12.0, "stable": true},
	{"name": "relative", "policy": 0, "limit": 12.0, "stable": true, "relative": true},
	{"name": "normal", "policy": 0, "limit": 12.0, "stable": true, "relative": true, "normal": true},
	{"name": "nearest", "policy": 2, "limit": 12.0, "stable": true, "relative": true, "normal": true, "release": true},
	{"name": "tangent", "policy": 2, "limit": 12.0, "stable": true, "relative": true, "normal": true, "release": true, "tangent": true},
	{"name": "bounded", "policy": 0, "limit": 12.0, "stable": true, "relative": true, "normal": true, "bounded": true},
	{"name": "bounded_tangent", "policy": 2, "limit": 12.0, "stable": true, "relative": true, "normal": true, "release": true, "tangent": true, "bounded": true},
	{"name": "segmented", "policy": 0, "limit": 12.0, "stable": true, "relative": true, "normal": true, "bounded": true, "segmented": true},
	{"name": "segmented_tangent", "policy": 2, "limit": 12.0, "stable": true, "relative": true, "normal": true, "release": true, "tangent": true, "bounded": true, "segmented": true},
	{"name": "finish", "policy": 0, "limit": 12.0, "stable": true, "relative": true, "normal": true, "bounded": true, "segmented": true, "finish": true},
	{"name": "finish_tangent", "policy": 2, "limit": 12.0, "stable": true, "relative": true, "normal": true, "release": true, "tangent": true, "bounded": true, "segmented": true, "finish": true},
]


func _attach_recorder(ball: PinballBall) -> void:
	if not _config.get("stable", false):
		super._attach_recorder(ball)
		return
	var recorder := Stable.new(ball)
	if _config.get("release", false):
		recorder.recovery = SafeRelease.new()
		(recorder.recovery as SafeRelease).use_tangents = _config.get("tangent", false)
		recorder.recovery.distance_limited = false
	recorder.normal_for_new_contact = true
	recorder.refresh_clear_state = _config.get("state", true)
	recorder.exact_native_time = _config.get("clock", true)
	recorder.relative_enemies = _config.get("relative", false)
	recorder.normal_all = _config.get("normal", false)
	recorder.bounded_clearance = _config.get("bounded", false)
	recorder.finish_contacts = _config.get("finish", false)
	recorder.recovery.policy = int(_config.policy) as ReleaseRecovery.Policy
	recorder.recovery.limit = _config.limit
	recorder.native_response = ball._resolve_contact
	recorder.contact_recorded = ball._record_contact
	ball._motion = recorder


func _run() -> void:
	_config = METHODS[0]
	_make_main(false)
	await physics_frame
	await physics_frame
	for node: Node in _main.get_node("Playfield").find_children("*", "StaticBody2D", true, false):
		if not node is PinballFlipper:
			_static_bodies.append({"node": node, "layer": node.collision_layer})
	for config: Dictionary in METHODS:
		if "--finish" in OS.get_cmdline_user_args() and not config.get("finish", false):
			continue
		if "--segmented" in OS.get_cmdline_user_args() and not config.get("segmented", false):
			continue
		if "--bounded" in OS.get_cmdline_user_args() and not config.get("bounded", false):
			continue
		if "--second" in OS.get_cmdline_user_args() and config.name not in ["normal", "nearest", "tangent"]:
			continue
		_config = config
		var rows: Array[Dictionary] = []
		for environment: Dictionary in [ENVIRONMENTS[0], ENVIRONMENTS[10], ENVIRONMENTS[9], ENVIRONMENTS[11]]:
			for ordinary: bool in [false, true]:
				if ordinary and environment.name in ["flipper_only", "full_reference"]:
					continue
				for fixture: Vector3 in _fixtures():
					rows.append(await _scenario(fixture, environment, ordinary))
		_write("stable_" + str(config.name) + ".json", {"cases": rows})
		print("Stability experiment: ", config.name, "; cases: ", rows.size())
	_main.free()
	_write("stable_audit.json", {"checks": _checks, "failures": _failures, "methods": METHODS})
	quit(0 if _failures == 0 else 1)


func _new_enemy(position: Vector2, routes: bool = false) -> Enemy:
	if not _config.get("segmented", false):
		return super._new_enemy(position, routes)
	var actor := load("res://enemies/enemy.tscn").instantiate() as Enemy
	var values := {}
	for property: Dictionary in actor.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_STORAGE:
			values[property.name] = actor.get(property.name)
	actor.set_script(TrackedEnemy)
	for key: String in values:
		actor.set(key, values[key])
	actor.position = position
	actor.death_cue = null
	_main.get_node("Playfield").add_child(actor)
	actor.prepare(actor.grow_duration)
	(actor as CausalEnemy).trace_enabled = true
	if routes:
		actor.start(_main.routes)
	return actor


func _collect_integration(result: Dictionary, recorder: Recorder) -> void:
	super._collect_integration(result, recorder)
	var overlaps := _obstacles(_main.ball, _main.ball.radius, 6)
	var depth := 0.0
	var disabled := _main.flippers.is_target_disabled(_main.ball.get_instance_id())
	for entry: Dictionary in overlaps:
		if entry.kind != "flipper" or not disabled:
			depth = maxf(depth, entry.depth_px)
	result["final_overlap_max_px"] = maxf(result.get("final_overlap_max_px", 0.0), depth)
	result["overlap_updates"] = result.get("overlap_updates", 0) + int(depth > 0.0)
	for event: Dictionary in recorder.events:
		var introduced: float = event.get("introduced_depth_max_px", 0.0)
		result["introduced_depth_max_px"] = maxf(result.get("introduced_depth_max_px", 0.0), introduced)
		result["introduced_over_margin"] = result.get("introduced_over_margin", 0) + int(introduced > 0.03)
	if recorder is Stable and not recorder.cap_snapshot.is_empty():
		if not result.has("cap_constraints"):
			result["cap_constraints"] = []
		result.cap_constraints.append(recorder.cap_snapshot.duplicate(true))
	if recorder is Stable:
		result["clear_tails"] = result.get("clear_tails", 0) + recorder.clear_tails


func _fixtures() -> Array[Vector3]:
	if "--smoke" in OS.get_cmdline_user_args():
		return [Vector3(.99, 12, 36)]
	var result: Array[Vector3] = []
	for ratio: float in [.05, .15, .30, .50, .70, .90, .99]:
		for gap: float in [3, 12, 36, 72]:
			for offset: float in [-36, 0, 36]:
				result.append(Vector3(ratio, gap, offset))
	return result
