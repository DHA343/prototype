extends Node2D

const Preview = preload("res://experiments/flippers/preview.gd")
const ShotGuard = preload("res://experiments/flippers/shot_guard.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")

var paused: bool = false
var duration_ms: float = 40.0
var previews: Array[Preview] = []
var _statuses: Array[Label] = []
var _pause_button: Button
var _duration_field: SpinBox
var _ball_count_button: Button
var _scenario_time: float = -1.0


func _ready() -> void:
	_build_views()
	_build_controls()
	_update_labels()


func _physics_process(delta: float) -> void:
	if not paused:
		advance(delta)
	for preview: Preview in previews:
		preview._shot_velocity = preview.predict_shot()
		preview.queue_redraw()
	_update_labels()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var edit := _duration_field.get_line_edit()
		if edit.has_focus() and not _duration_field.get_global_rect().has_point(event.position):
			_duration_field.apply()
			edit.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_P:
				set_paused(not paused)
			KEY_N:
				if paused:
					advance(1.0 / 60.0)
			KEY_R:
				reset_balls()


func advance(delta: float) -> void:
	var remaining := delta
	while remaining > 0.000001:
		var left := Input.is_action_pressed(&"pinball_left")
		var right := Input.is_action_pressed(&"pinball_right")
		var step := minf(Preview.STEP, remaining)
		if _scenario_time >= 0.0:
			left = _scenario_time < 0.06 - 0.000001
			right = left
			step = minf(step, (0.06 if left else 0.3) - _scenario_time)
			_scenario_time += step
			if _scenario_time >= 0.3 - 0.000001:
				_scenario_time = -1.0
		for preview: Preview in previews:
			preview.advance_inputs(step, left, right)
		remaining -= step


func set_paused(value: bool) -> void:
	paused = value
	_pause_button.text = "再開（P）" if paused else "一時停止（P）"
	_duration_field.editable = paused


func reset_balls() -> void:
	_scenario_time = -1.0
	for preview: Preview in previews:
		(preview.flippers as ShotGuard).reset_stats()
		preview.reset_ball()


func replay_tip_shot() -> void:
	reset_balls()
	for preview: Preview in previews:
		var flipper := preview.flippers.items[0] as FixedFlipper
		var points := flipper.world_polygon_at(flipper.global_transform)
		var top := points[0].lerp(points[1], 0.92)
		preview.ball.reset_at(top + Vector2.UP * (preview.ball.radius + 4.0), Vector2(0.0, 300.0))
	_scenario_time = 0.0
	set_paused(false)


func set_ball_count(count: int) -> void:
	for preview: Preview in previews:
		preview.set_ball_count(count)
	reset_balls()
	_ball_count_button.text = "20球に切替" if count == 1 else "1球に切替"


func _build_views() -> void:
	for index in 2:
		var container := get_node("LeftView" if index == 0 else "RightView")
		var world := container.get_node("World") as SubViewport
		world.canvas_transform = Transform2D(0.0, Vector2(-240.0, 0.0))
		var preview := world.get_node("Preview") as Preview
		var guard := preview.flippers as ShotGuard
		guard.mode = index as ShotGuard.Mode
		guard.duration_ms = duration_ms
		(preview.get_node("Playfield") as CanvasLayer).offset = Vector2(-240.0, 0.0)
		preview.set_physics_process(false)
		previews.append(preview)


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ComparisonControls"
	layer.layer = 100
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(24.0, 12.0)
	box.add_theme_constant_override("separation", 8)
	layer.add_child(box)
	_label(box, "打球後の無効化比較：同じ入力・別々の物理空間", 23)
	_label(box, "A / 左：左フリッパー　D / 右：右フリッパー　Space：両方　P：停止再開　N：1更新　R：リセット", 20)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_pause_button = _button(row, "一時停止（P）", func() -> void: set_paused(not paused))
	_button(row, "両方リセット（R）", reset_balls)
	_button(row, "左先端から打球を再現", replay_tip_shot)
	_ball_count_button = _button(row, "20球に切替", func() -> void:
		set_ball_count(20 if previews[0].balls.size() == 1 else 1))
	_label(row, "④の無効化時間（停止中に変更）", 20)
	_duration_field = SpinBox.new()
	_duration_field.min_value = 5.0
	_duration_field.max_value = 150.0
	_duration_field.step = 5.0
	_duration_field.suffix = "ms"
	_duration_field.value = duration_ms
	_duration_field.editable = false
	row.add_child(_duration_field)
	_duration_field.value_changed.connect(func(value: float) -> void:
		duration_ms = value
		(previews[1].flippers as ShotGuard).duration_ms = value)
	_duration_field.get_line_edit().text_submitted.connect(func(_text: String) -> void:
		_duration_field.apply()
		_duration_field.get_line_edit().release_focus.call_deferred())
	for index in 2:
		var title := _label(layer, "③ 打球後、下降するまで左右を通す" if index == 0
			else "④ 短時間だけ左右を通す・下降したら即解除", 23)
		title.position = Vector2(index * 960.0 + 24.0, 132.0)
		var status := _label(layer, "", 20)
		status.position = Vector2(index * 960.0 + 24.0, 956.0)
		_statuses.append(status)


func _update_labels() -> void:
	for index in 2:
		var preview := previews[index]
		var guard := preview.flippers as ShotGuard
		var suppressed := 0
		var active := 0
		var max_separation := 0.0
		for target: PinballBall in preview.balls:
			active += int(target.active)
			if guard.is_suppressed(target):
				suppressed += 1
			max_separation = maxf(max_separation, target.max_separation)
		var state := "%d球（稼働 %d）　無効 %d球／有効 %d球" % [preview.balls.size(),
			active, suppressed, active - suppressed]
		if index == 1 and preview.balls.size() == 1 and guard.is_suppressed(preview.ball):
			state += "（残り %.1f ms）" % guard.remaining_ms(preview.ball)
		_statuses[index].text = "%s　%s\n打球 %d　下降で解除 %d　時間で解除 %d\n球の速度 (%.0f, %.0f)　最大位置補正 %.2f px" % [
			"停止中" if paused else "実行中", state, guard.shot_count,
			guard.descent_releases, guard.time_releases,
			preview.ball.velocity.x, preview.ball.velocity.y, max_separation]


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _label(parent: Node, text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	parent.add_child(label)
	return label
