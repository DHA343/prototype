extends "res://experiments/flippers/method_preview.gd"

var _forced_step: bool = false


func _configure_balls() -> void:
	for index in 2:
		(previews[index].flippers as ShotGuard).mode = ShotGuard.Mode.UNTIL_DESCENDING
		for target: PinballBall in previews[index].balls:
			var ball := target as MatrixBall
			ball.rotation_sweep = index == 1
			ball.guard_enabled = true
			ball.iterative = true
			ball.final_response = false


func advance(delta: float) -> void:
	var left := true if _forced_step else Input.is_action_pressed(&"pinball_left")
	var right := false if _forced_step else Input.is_action_pressed(&"pinball_right")
	for index in 2:
		_advance_candidate(delta, left, right, index)
	if _forced_step:
		_forced_step = false
		set_paused(true)


func reset_balls() -> void:
	_forced_step = false
	super.reset_balls()
	for preview: Preview in previews:
		for target: PinballBall in preview.balls:
			(target as MatrixBall).shots = 0


func replay_case(index: int) -> void:
	set_ball_count(1)
	for preview: Preview in previews:
		if index != 2:
			preview.flippers.advance(15.0 / 600.0, true, false)
		var fixed := preview.flippers.items[0] as FixedFlipper
		var points := fixed.world_polygon_at(fixed.global_transform)
		var point := points[0].lerp(points[1], 0.65 if index == 1 else 0.95)
		# Match the audit's incoming velocity after the preview's gravity update.
		var incoming := Vector2(0, -600 if index == 0 else 300)
		preview.ball.reset_at(point + Vector2.UP * 36,
			incoming - Vector2.DOWN * preview.ball.gravity / 60.0)
	_forced_step = true
	set_paused(false)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ContactControls"
	layer.layer = 100
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 12)
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	_label(box, "検出だけを比較：両方とも全体分割なし・接触後は曲がった経路を追う", 23)
	_label(box, "A / D / Space：フリッパー　P：停止再開　N：1更新　再現ボタンは1更新後に停止", 20)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_pause_button = _button(row, "一時停止（P）", func() -> void: set_paused(not paused))
	_button(row, "リセット（R）", reset_balls)
	_button(row, "非接触なのに打球される例", func() -> void: replay_case(0))
	_button(row, "板が止まった後の誤打球", func() -> void: replay_case(1))
	_button(row, "先端付近の大きな位置補正", func() -> void: replay_case(2))
	_ball_count_button = _button(row, "20球に切替", func() -> void:
		set_ball_count(20 if previews[0].balls.size() == 1 else 1))
	for index in 2:
		var title := _label(layer, "球の直線経路 × 更新後の板" if index == 0
			else "球と板を同時刻の途中姿勢で検査", 22)
		title.position = Vector2(index * 960 + 24, 132)
		var status := _label(layer, "", 20)
		status.position = Vector2(index * 960 + 24, 956)
		_statuses.append(status)


func _update_labels() -> void:
	for index in 2:
		var preview := previews[index]
		var shots := 0
		var contacts := 0
		for target: PinballBall in preview.balls:
			shots += (target as MatrixBall).shots
			contacts += (target as MatrixBall).contacts
		_statuses[index].text = "%s　%d球　打球 %d　接触処理 %d\n代表球の速度 (%.1f, %.1f) px/s" % [
			"停止中" if paused else "実行中", preview.balls.size(), shots, contacts,
			preview.ball.velocity.x, preview.ball.velocity.y]
