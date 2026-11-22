extends "res://experiments/flippers/release_preview.gd"

const TraceMotion = preload("res://experiments/flippers/tests/release_motion.gd")
const TITLES: Array[String] = ["現行解除", "安全分離12 px", "安全分離・距離制限なし"]
const PRESETS: Array[Vector3] = [Vector3(0.5, 36, 0), Vector3(0.7, 36, 0),
	Vector3(0.9, 3, 0), Vector3(0.15, 3, 0)]

var replaying: bool = false
var replay_paused: bool = false
var frames: int = 0
var max_correction: float = 0.0
var capped_updates: int = 0
var replay_enemy: Enemy
var preset: int = 0


func _init() -> void:
	mode = 0


func _ready() -> void:
	super._ready()
	main.spawner.enabled = false


func set_mode(value: int) -> void:
	replaying = false
	replay_paused = false
	if is_instance_valid(replay_enemy):
		replay_enemy.free()
	super.set_mode(1 if value == 0 else 5)
	mode = value
	(main.ball._motion as Motion).recovery.distance_limited = value != 2
	main.spawner.enabled = false
	_show_mode()


func replay(index: int) -> void:
	set_mode(mode)
	preset = index
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.flippers.reset_input()
	main.flippers.swing_angle = 18.0
	main.flippers.raise_speed = 600.0
	main.flippers.return_speed = 420.0
	main.flippers.pass_until_descending = true
	for item: PinballFlipper in main.flippers.items:
		item.collision_layer = 2
	var ball := main.ball
	var trace := TraceMotion.new(ball)
	trace.normal_for_new_contact = true
	trace.recovery.policy = Recovery.Policy.CURRENT if mode == 0 else Recovery.Policy.SAFE
	trace.recovery.limit = 12.0
	trace.recovery.distance_limited = mode != 2
	trace.native_response = ball._resolve_contact
	trace.contact_recorded = ball._record_contact
	ball._motion = trace
	ball.radius = 24.0
	ball.gravity = 1500.0
	ball.max_speed = 3600.0
	ball.hit_sound = null
	ball.collision_mask = 6
	var points := (main.flippers.items[0] as TableFlipper).world_polygon_at(main.flippers.items[0].global_transform)
	var input: Vector3 = PRESETS[index]
	ball.reset_at(points[0].lerp(points[1], input.x) + Vector2.UP * 28, Vector2(0, 300))
	replay_enemy = load("res://enemies/enemy.tscn").instantiate() as Enemy
	replay_enemy.death_cue = null
	replay_enemy.position = ball.global_position + Vector2(input.z, -(54.0 + input.y))
	main.get_node("Playfield").add_child(replay_enemy)
	replay_enemy.prepare(replay_enemy.grow_duration)
	frames = 0
	max_correction = 0.0
	capped_updates = 0
	replaying = true
	_show_mode()


func _physics_process(_delta: float) -> void:
	if replaying and not replay_paused:
		step_replay()


func step_replay() -> void:
	if not replaying:
		return
	var plans := main.flippers.plan_motion(true, true)
	main.flippers.advance(1.0 / 60.0, true, true)
	if is_instance_valid(replay_enemy):
		replay_enemy.prepare(1.0 / 60.0)
		replay_enemy.advance(1.0 / 60.0)
	main.ball.advance(1.0 / 60.0, plans)
	var trace := main.ball._motion as TraceMotion
	frames += 1
	for event: Dictionary in trace.events:
		max_correction = maxf(max_correction, event.correction_px)
	if not trace.recovery.tick.is_empty():
		var offset: Array = trace.recovery.tick.correction
		max_correction = maxf(max_correction, Vector2(offset[0], offset[1]).length())
	capped_updates += int(trace.discarded_seconds > 0.0)
	if trace.recovery.failed or frames >= 60:
		replaying = false
	_show_mode()


func _show_mode() -> void:
	label.text = "実験用：" + TITLES[mode]
	label.text += "\n1/2/3：方式切替　4/5/6：既知3配置　7：最大補正例"
	label.text += "\nP：再現の停止/再開　N：停止中に1更新　R：通常状態へリセット"
	if frames > 0 and not main.is_physics_processing():
		label.text += "\n再現%d：%d/60更新　最大補正 %.2f px　上限到達 %d" % [preset + 1, frames, max_correction, capped_updates]
		if (main.ball._motion as TraceMotion).recovery.failed:
			label.text += "　候補なし・未解消で終了"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_3:
		set_mode(key.keycode - KEY_1)
	elif key.keycode >= KEY_4 and key.keycode <= KEY_7:
		replay(key.keycode - KEY_4)
	elif key.keycode == KEY_P:
		replay_paused = not replay_paused
	elif key.keycode == KEY_N and replay_paused:
		step_replay()
	elif key.keycode == KEY_R:
		set_mode(mode)
