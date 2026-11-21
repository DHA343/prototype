extends RefCounted

const Flipper = preload("res://experiments/flippers/shot_flipper.gd")


static func install(main: PinballLab, rule: int = Flipper.Rule.THREE_CONDITIONS) -> void:
	assert(not main.is_inside_tree(), "Install the experiment before entering the tree")
	for name: String in ["LeftFlipper", "RightFlipper"]:
		var item := main.get_node("Playfield/Flippers/" + name) as TableFlipper
		var pivot := item.pivot_socket
		var tip := item.tip_socket
		var side := item.side
		var thickness := item.extra_thickness
		item.set_script(Flipper)
		item.pivot_socket = pivot
		item.tip_socket = tip
		item.side = side
		item.extra_thickness = thickness
		item.set("rule", rule)
