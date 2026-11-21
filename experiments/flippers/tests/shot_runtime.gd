extends RefCounted

const Trace = preload("res://experiments/flippers/tests/shot_motion.gd")


static func run(preview: Node) -> Dictionary:
	var main: PinballLab = preview.get("main")
	var original_label: String = preview.get("label").text
	main.set_physics_process(false)
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.spawner.enabled = false
	for enemy: Enemy in main.enemies:
		enemy.free()
	main.enemies.clear()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var fixture: Dictionary = data.cases.filter(func(row: Dictionary) -> bool:
		return row.suite == "moving_edges" and int(row.id) == 96)[0].case
	var rows: Array[Dictionary] = []
	for rule in 3:
		main.flippers.reset_input()
		main.flippers.swing_angle = 18.0
		main.flippers.raise_speed = 600.0
		main.flippers.return_speed = 420.0
		main.flippers.pass_until_descending = true
		for item: PinballFlipper in main.flippers.items:
			item.set("rule", rule)
			item.collision_layer = 8 << item.side
		var ball := main.ball
		ball.radius = fixture.radius
		ball.gravity = 0.0
		ball.max_speed = 3600.0
		ball.collision_mask = 8 << int(fixture.side)
		var recorder := Trace.new(ball)
		recorder.native_response = ball._resolve_contact
		recorder.contact_recorded = ball._record_contact
		ball._motion = recorder
		ball.reset_at(Vector2(fixture.start[0], fixture.start[1]),
			Vector2(fixture.velocity[0], fixture.velocity[1]).limit_length(3600))
		var item := main.flippers.items[int(fixture.side)]
		var plan := item.plan_motion(true, 18.0, 600.0)
		main.flippers.advance(1.0 / fixture.rate, true, true)
		ball.advance(1.0 / fixture.rate, [plan])
		rows.append({"rule": rule, "first": recorder.events[0].duplicate(true),
			"position": [ball.global_position.x, ball.global_position.y],
			"velocity": [ball.velocity.x, ball.velocity.y]})
	var controls: Array[Dictionary] = []
	for code: Key in [KEY_1, KEY_2, KEY_3]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = true
		preview.call("_unhandled_key_input", event)
		controls.append({"rule": preview.get("rule"), "label": preview.get("label").text,
			"flippers": main.flippers.items.map(func(item: PinballFlipper) -> int: return item.get("rule"))})
	var result := {"initial_label": original_label, "fixture": fixture, "results": rows,
		"controls": controls, "scope": "Godot AI live experimental preview; manual fixture replay; no scene saved"}
	var file := FileAccess.open("res://experiments/flippers/evidence/shot_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	return result
