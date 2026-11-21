extends RefCounted


static func run(main: PinballLab) -> Dictionary:
	main.set_physics_process(false)
	main.get_node("EnemySpawner").enabled = false
	for child: Node in main.get_node("Playfield").get_children():
		if child is Enemy:
			child.free()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
		"res://experiments/flippers/evidence/continuous_audit.json"))
	var fixture: Dictionary = {}
	for row: Dictionary in data.cases:
		if row.suite == "moving_edges" and int(row.id) == 87:
			fixture = row.case
			break
	var rows: Array[Dictionary] = []
	for mode: int in [0, 2, 4, 8, -1]:
		main.flippers.reset_input()
		main.flippers.swing_angle = 18.0
		main.flippers.raise_speed = 600.0
		main.flippers.return_speed = 420.0
		main.flippers.pass_until_descending = true
		for index in main.flippers.items.size():
			main.flippers.items[index].collision_layer = 8 << index
		var ball := main.ball
		ball.radius = fixture.radius
		ball.gravity = 0.0
		ball.max_speed = 3600.0
		ball.collision_mask = 8
		var path := "res://experiments/flippers/tests/native_motion.gd"
		if mode > 0:
			path = "res://experiments/flippers/tests/refined_motion.gd"
		elif mode < 0:
			path = "res://experiments/flippers/tests/continuous_motion.gd"
		var recorder: PinballMotion = load(path).new(ball)
		if mode > 0:
			recorder.set("iterations", mode)
		recorder.set("native_response", ball._resolve_contact)
		recorder.contact_recorded = ball._record_contact
		ball._motion = recorder
		ball.reset_at(Vector2(fixture.start[0], fixture.start[1]),
			Vector2(fixture.velocity[0], fixture.velocity[1]).limit_length(3600.0))
		var item := main.flippers.items[0] as TableFlipper
		var plans: Array[PinballFlipper.Swing] = [item.plan_motion(true, 18.0, 600.0)]
		main.flippers.advance(1.0 / fixture.rate, true, true)
		ball.advance(1.0 / fixture.rate, plans)
		var events: Array = recorder.get("events")
		rows.append({"mode": mode, "first": events[0],
			"position": [ball.global_position.x, ball.global_position.y],
			"velocity": [ball.velocity.x, ball.velocity.y]})
	var evidence := {"fixture": fixture, "results": rows,
		"scope": "Godot AI live main, automatic physics disabled; small-radius corner input 87; runtime only"}
	var file := FileAccess.open(
		"res://experiments/flippers/evidence/refinement_runtime.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence, "\t"))
	return evidence
