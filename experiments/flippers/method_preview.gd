extends "res://experiments/flippers/comparison.gd"

const MatrixBall = preload("res://experiments/flippers/tests/matrix_ball.gd")


func _enter_tree() -> void:
	for path: String in ["LeftView/World/Preview/Playfield/Ball", "RightView/World/Preview/Playfield/Ball"]:
		var target := get_node(path) as PinballBall
		target.set_script(MatrixBall)
		target.radius = 24
		target.gravity = 1500
		target.max_speed = 3600


func _input(_event: InputEvent) -> void:
	pass


func _build_views() -> void:
	super._build_views()
	_configure_balls()


func _configure_balls() -> void:
	for index in 2:
		(previews[index].flippers as ShotGuard).mode = ShotGuard.Mode.UNTIL_DESCENDING
		for target: PinballBall in previews[index].balls:
			var candidate := target as MatrixBall
			candidate.rotation_sweep = true
			candidate.guard_enabled = true
			candidate.iterative = index == 0
			candidate.final_response = index == 1


func advance(delta: float) -> void:
	var left := Input.is_action_pressed(&"pinball_left")
	var right := Input.is_action_pressed(&"pinball_right")
	if _scenario_time >= 0:
		left = _scenario_time < 4.0 / 60.0 - 0.000001
		right = left
		_scenario_time += delta
		if _scenario_time >= 0.3:
			_scenario_time = -1
	previews[0].advance_inputs(delta, left, right)
	_advance_candidate(delta, left, right)


func _advance_candidate(delta: float, left: bool, right: bool, view_index: int = 1) -> void:
	var preview := previews[view_index]
	var swings := preview.flippers.plan_motion(left, right)
	preview.flippers.advance(delta, left, right)
	for index in preview.balls.size():
		var target := preview.balls[index]
		var id := target.get_instance_id()
		if target.active:
			target.advance(delta, swings)
			if preview.boundary.to_local(target.global_position).y > preview.boundary.bottom + 120:
				target.active = false
				target.visible = false
				preview._respawn_remaining[id] = Preview.RESPAWN_DELAY
				(preview.flippers as ShotGuard).forget_ball(target)
		else:
			preview._respawn_remaining[id] -= delta
			if preview._respawn_remaining[id] <= 0:
				target.reset_at(preview._spawn_for(index))
				preview._respawn_remaining.erase(id)


func set_paused(value: bool) -> void:
	paused = value
	_pause_button.text = "再開（P）" if paused else "一時停止（P）"


func set_ball_count(count: int) -> void:
	super.set_ball_count(count)
	_configure_balls()


func reset_balls() -> void:
	super.reset_balls()
	for preview: Preview in previews:
		for target: PinballBall in preview.balls:
			var candidate := target as MatrixBall
			candidate.contacts = 0
			candidate.updates = 0
			candidate.cap_steps = 0
			candidate.end_corrections = 0
			candidate.max_end_correction = 0
			candidate.extra_end_contacts = 0


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ComparisonControls"
	layer.layer = 100
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 12)
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	_label(box, "移動方式の比較：厚み48 px・無効化③は共通", 23)
	_label(box, "A / 左・D / 右・Space：フリッパー　P：停止再開　N：1更新　R：リセット", 20)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_pause_button = _button(row, "一時停止（P）", func() -> void: set_paused(not paused))
	_button(row, "両方リセット（R）", reset_balls)
	_button(row, "左先端から打球を再現", replay_tip_shot)
	_ball_count_button = _button(row, "20球に切替", func() -> void:
		set_ball_count(20 if previews[0].balls.size() == 1 else 1))
	for index in 2:
		var title := _label(layer, "現行：時間分割＋途中姿勢検査＋接触ごとの再計算" if index == 0
			else "候補：分割なし＋途中姿勢検査＋終点移動・接触応答", 22)
		title.position = Vector2(index * 960 + 24, 132)
		var status := _label(layer, "", 20)
		status.position = Vector2(index * 960 + 24, 956)
		_statuses.append(status)


func _update_labels() -> void:
	for index in 2:
		var preview := previews[index]
		var suppressed := 0
		var contacts := 0
		var caps := 0
		var correction := 0.0
		for target: PinballBall in preview.balls:
			var candidate := target as MatrixBall
			suppressed += int((preview.flippers as ShotGuard).is_suppressed(target))
			contacts += candidate.contacts
			caps += candidate.cap_steps
			correction = maxf(correction, maxf(candidate.max_separation, candidate.max_end_correction))
		_statuses[index].text = "%s　%d球　無効 %d球\n接触処理 %d　8回上限 %d\n手動の上向き補正 %.2f px" % [
			"停止中" if paused else "実行中", preview.balls.size(), suppressed, contacts, caps, correction]
