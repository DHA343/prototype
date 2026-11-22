extends Node

const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Separation = preload("res://experiments/flippers/separation.gd")
const MODES: Array[Dictionary] = [
	{"name": "現行", "rule": 0, "normal": false},
	{"name": "3条件のみ", "rule": 2, "normal": false},
	{"name": "新接触の法線分離のみ", "rule": 0, "normal": true},
	{"name": "3条件＋新接触の法線分離", "rule": 2, "normal": true},
]

var main: PinballLab
var label: Label
var mode: int = 3


func _ready() -> void:
	main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(main, int(MODES[mode].rule))
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
	var config: Dictionary = MODES[mode]
	for item: PinballFlipper in main.flippers.items:
		item.set("rule", int(config.rule))
	var ball := main.ball
	ball._motion.reset()
	if config.normal:
		var candidate := Separation.new(ball)
		candidate.native_response = ball._resolve_contact
		ball._motion = candidate
	else:
		ball._motion = PinballMotion.new(ball)
		ball._motion.native_contact = ball._resolve_contact
	ball._motion.contact_recorded = ball._record_contact
	main.reset_ball()
	label.text = "実験用：" + str(config.name)
	label.text += "\n1 / 2 / 3 / 4：方式切替・球リセット　R：球リセット"
	label.text += "\nA / D / Space：既存操作　検出B・③・接触上限8回を維持"


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode >= KEY_1 and key.keycode <= KEY_4:
		set_mode(key.keycode - KEY_1)
	elif key.keycode == KEY_R:
		main.reset_ball()
