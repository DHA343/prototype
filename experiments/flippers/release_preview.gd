extends Node

const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Manager = preload("res://experiments/flippers/release_flippers.gd")
const Motion = preload("res://experiments/flippers/release_motion.gd")
const Recovery = preload("res://experiments/flippers/release.gd")
const LABELS: Array[String] = ["従来B", "3条件＋法線分離・現行解除", "重なり解消まで解除延期",
	"安全分離 上限3 px", "安全分離 上限6 px", "安全分離 上限12 px"]

var main: PinballLab
var label: Label
var mode: int = 1


func _ready() -> void:
	main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(main, 2)
	Manager.install(main)
	add_child(main)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(18, 18)
	label.add_theme_font_size_override("font_size", 24)
	overlay.add_child(label)
	set_mode(mode)


func set_mode(value: int) -> void:
	mode = value
	var ball := main.ball
	ball._motion.reset()
	(main.flippers as Manager).controllers.erase(ball.get_instance_id())
	for item: PinballFlipper in main.flippers.items:
		item.set("rule", 0 if mode == 0 else 2)
	if mode == 0:
		ball._motion = PinballMotion.new(ball)
		ball._motion.separate_new_contacts = false
		ball._motion.native_contact = ball._resolve_contact
	else:
		var candidate := Motion.new(ball)
		candidate.recovery.policy = mini(mode - 1, 2) as Recovery.Policy
		candidate.recovery.limit = [3.0, 6.0, 12.0][maxi(0, mode - 3)]
		candidate.native_response = ball._resolve_contact
		ball._motion = candidate
	ball._motion.contact_recorded = ball._record_contact
	main.reset_ball()
	main.set_physics_process(true)
	main.get_node("Playfield/ShotGuide").set_physics_process(true)
	label.text = "実験用：" + LABELS[mode]
	label.text += "\n1～6：方式切替　R：リセット　A/D/Space：既存操作"


func _process(_delta: float) -> void:
	var motion := main.ball._motion as Motion
	if motion != null and motion.recovery.failed and main.is_physics_processing():
		main.set_physics_process(false)
		main.get_node("Playfield/ShotGuide").set_physics_process(false)
		label.text += "\n安全な候補なし：未解消で試行停止。Rで再試行"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_6:
		set_mode(key.keycode - KEY_1)
	elif key.keycode == KEY_R:
		set_mode(mode)
