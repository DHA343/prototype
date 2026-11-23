extends "res://experiments/flippers/tests/value_audit.gd"

const GuardTrace = preload("res://experiments/flippers/tests/guard_trace.gd")
const ExitGuard = preload("res://experiments/flippers/tests/guard_exit.gd")

var _early: bool = false
var _same_tick: bool = false
var _episodes: Array[Dictionary] = []
var _ongoing: Dictionary = {}
var _recent: Array[Dictionary] = []
var _pending: Array[Dictionary] = []
var _guard_counts: Dictionary = {}


func _run() -> void:
	_seconds = 120
	_tag = "isolated_"
	var seeds: Array[int] = [113, 271]
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--early": _early = true
		if argument == "--immediate": _same_tick = true
		if argument.begins_with("--seeds="):
			seeds.clear()
			for value: String in argument.get_slice("=", 1).split(","): seeds.append(int(value))
	for episode_seed: int in seeds:
		_episodes.clear()
		_ongoing.clear()
		_recent.clear()
		_pending.clear()
		_guard_counts = {"shot_cycles": 0, "releases": 0, "internal_releases": 0,
			"guarded_ticks": 0, "guarded_inside_ticks": 0, "one_board_only_clear_ticks": 0,
			"guarded_inside_end_ticks": 0, "external_down_turns": 0}
		var measured := await _episode("B", "held", episode_seed)
		measured["guard_counts"] = _guard_counts
		measured["guard_episodes"] = _episodes
		measured["policy"] = "immediate" if _same_tick else ("early" if _early else "current")
		_write("guard_" + str(measured.policy) + "_" + str(episode_seed) + ".json", measured)
		print(measured.policy, " seed", episode_seed, ": ", _guard_counts)
	quit(0)


func _make_probe() -> Probe:
	install_manager(_main, _early)
	var trace := GuardTrace.new(_main.ball)
	trace.same_tick_descent = _same_tick
	return trace


static func install_manager(main: PinballLab, early: bool) -> void:
	var saved := {}
	var items := main.flippers.items
	for property: Dictionary in main.flippers.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_STORAGE:
			saved[property.name] = main.flippers.get(property.name)
	main.flippers.set_script(ExitGuard)
	for key: String in saved: main.flippers.set(key, saved[key])
	main.flippers.items = items
	(main.flippers as ExitGuard).early_exit = early


func _observe_tick(before: Vector2, bits: int) -> void:
	super._observe_tick(before, bits)
	var probe := _probe as GuardTrace
	probe.clock_frame = _clock + 1
	var row := probe.tick.duplicate(true)
	row.frame = _clock
	row["bits"] = bits
	row["ball_active"] = _main.ball.active
	_guard_counts.guarded_inside_end_ticks += int(row.guard_after and minf(row.end_gap[0], row.end_gap[1]) < 0)
	for episode: Dictionary in _pending:
		if _clock <= int(episode.release_frame) + 60: episode.tail.append(row)
	_pending = _pending.filter(func(episode: Dictionary) -> bool:
		return _clock < int(episode.release_frame) + 60)
	if row.guard_before:
		_guard_counts.guarded_ticks += 1
		var inside: bool = row.start_gap[0] <= 0 or row.start_gap[1] <= 0
		_guard_counts.guarded_inside_ticks += int(inside)
		_guard_counts.one_board_only_clear_ticks += int((row.start_gap[0] > 0) != (row.start_gap[1] > 0))
	if not _ongoing.is_empty(): _ongoing.rows.append(row)
	if row.guard_before and not row.guard_after_refresh:
		_guard_counts.releases += 1
		var inside: bool = row.start_gap[0] <= 0 or row.start_gap[1] <= 0
		_guard_counts.internal_releases += int(inside)
		_finish(inside, "descent" if row.next_velocity[1] > 1 else "exit", -1)
	for index: int in probe.events.size():
		var event: Dictionary = probe.events[index]
		_guard_counts.external_down_turns += int(event.guard and event.actor_kind != "flipper" \
			and event.incoming[1] < 0 and event.velocity[1] > 1)
		if event.shot:
			_guard_counts.shot_cycles += 1
			_ongoing = {"shot_frame": _clock, "shot": event.duplicate(true),
				"prefix": _recent.duplicate(true), "rows": [row], "start_contact_index": index}
		if event.get("guard_released_after_external", false):
			_guard_counts.releases += 1
			_finish(false, "external_descent", index)
	if not _main.ball.active: _ongoing = {}
	_recent.append(row)
	if _recent.size() > 3: _recent.pop_front()


func _finish(inside: bool, reason: String, contact_index: int) -> void:
	if not _ongoing.is_empty():
		_ongoing["release_frame"] = _clock
		_ongoing["release_contact_index"] = contact_index
		_ongoing["internal"] = inside
		_ongoing["release_reason"] = reason
		_ongoing["tail"] = []
		if inside or _episodes.size() < 4:
			_episodes.append(_ongoing)
			_pending.append(_ongoing)
	_ongoing = {}
