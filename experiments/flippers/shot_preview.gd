extends Node

const Policy = preload("res://experiments/flippers/shot_policy.gd")

var main: PinballLab
var label: Label
var rule: int = 2


func _ready() -> void:
	main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(main, rule)
	add_child(main)
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	add_child(overlay)
	label = Label.new()
	label.position = Vector2(18, 18)
	label.add_theme_font_size_override("font_size", 24)
	overlay.add_child(label)
	_show_rule()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_1:
			rule = 0
		KEY_2:
			rule = 1
		KEY_3:
			rule = 2
		KEY_R:
			main.reset_ball()
			return
		_:
			return
	for item: PinballFlipper in main.flippers.items:
		item.set("rule", rule)
	main.reset_ball()
	_show_rule()


func _show_rule() -> void:
	label.text = "実験用：" + ["現行", "60°制限だけ解除", "3条件（上昇・上辺と両端・相対接近）"][rule]
	label.text += "\n1 / 2 / 3：方式切替・球リセット　R：球リセット\nA / D / Space：既存のフリッパー操作"
