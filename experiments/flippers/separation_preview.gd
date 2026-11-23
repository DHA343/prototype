extends Node

const Policy = preload("res://experiments/flippers/shot_policy.gd")
const Scenes = preload("res://experiments/flippers/separation_scenes.gd")
const ViewMotion = preload("res://experiments/flippers/separation_view_motion.gd")
const Overlay = preload("res://experiments/flippers/separation_overlay.gd")
const MODES: Array[String] = ["S：3条件＋従来の上向き分離", "B：3条件＋新接触のみ法線分離"]

var main: PinballLab
var mode: int = 1
var scene_index: int = 0
var variant: int = 0
var loading: bool = true
var playing: bool = false
var frames: int = 0
var speed: float = .125
var input: Dictionary = {}
var events: Array[Dictionary] = []
var max_correction: float = 0.0
var capped_updates: int = 0
var dropped: bool = false
var initial: Dictionary = {}
var scenes: Scenes = Scenes.new()
var overlay: Overlay
var _generation: int = 0
var _accumulator: float = 0.0
var _positions: PackedVector2Array = []
var _previous: Dictionary = {}
var _original_canvas: Transform2D
var _chosen: int = -1
var _max_event: int = -1
var _run_variant: int = 0
var _scene_box: OptionButton
var _mode_box: OptionButton
var _variant_box: OptionButton
var _play_button: Button
var _view_box: OptionButton
var _source_label: Label
var _status: Label
var _event_label: Label
var _details: PanelContainer
var _event_number: SpinBox
var _track_max: CheckBox
var _guides: CheckBox
var _ghost: CheckBox


func _ready() -> void:
	_original_canvas = get_viewport().canvas_transform
	_build_controls()
	reset_case(scene_index, mode)


func _exit_tree() -> void:
	get_viewport().canvas_transform = _original_canvas


func reset_case(index: int = -1, method: int = -1) -> void:
	_generation += 1
	var generation := _generation
	if not loading and frames > 0:
		_previous = {"scene": scene_index, "variant": _run_variant, "mode": mode,
			"positions": _positions.duplicate()}
	loading = true
	playing = false
	_accumulator = 0.0
	if index >= 0 and index != scene_index:
		_view_box.select(1 if index in [1, 2] else 0)
	if index >= 0: scene_index = index
	if method >= 0: mode = method
	if is_instance_valid(main): main.free()
	main = load("res://main/main.tscn").instantiate() as PinballLab
	Policy.install(main, 2)
	add_child(main)
	main.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	main.set_physics_process(false)
	main.spawner.enabled = false
	main.get_node("Playfield/ShotGuide").set_physics_process(false)
	main.get_node("Playfield/ShotGuide").visible = false
	main.get_node("Playfield/DebugSummon").process_mode = Node.PROCESS_MODE_DISABLED
	main.bumper_hit.disconnect(main.launcher.fire_from)
	main.ball.hit_sound = null
	for node: Node in main.get_node("Playfield").find_children("*", "", true, false):
		if node is PinballBumper: node.hit_sound = null
	await get_tree().physics_frame
	if generation != _generation: return
	await get_tree().physics_frame
	if generation != _generation: return
	var motion := ViewMotion.new(main.ball)
	motion.normal_new = mode == 1
	motion.audit_detection = false
	motion.native_response = main.ball._resolve_contact
	motion.contact_recorded = main.ball._record_contact
	main.ball._motion = motion
	input = scenes.prepare(main, scene_index, variant)
	_run_variant = variant
	initial = scenes.snapshot(main)
	frames = 0
	max_correction = 0.0
	capped_updates = 0
	dropped = false
	events.clear()
	_chosen = -1
	_max_event = -1
	_positions = PackedVector2Array([main.ball.global_position])
	overlay = Overlay.new()
	overlay.name = "ComparisonGuides"
	overlay.z_index = 100
	overlay.radius = main.ball.radius
	overlay.flippers = main.flippers.items
	overlay.actors = scenes.actors
	main.get_node("Playfield").add_child(overlay)
	if _previous.get("scene", -1) == scene_index and _previous.get("variant", -1) == variant:
		overlay.ghost = _previous.positions
	loading = false
	_scene_box.select(scene_index)
	_mode_box.select(mode)
	_variant_box.clear()
	if scene_index == 2:
		_variant_box.add_item("最大補正例 / 深さ0.20 px")
		_variant_box.add_item("深い重なり / 深さ48 px")
	else:
		_variant_box.add_item("ratio .5 / 旧深さ28.49")
		_variant_box.add_item("ratio .7 / 旧深さ40.59")
	_variant_box.select(variant)
	_variant_box.visible = scene_index in [2, 3]
	_event_number.set_value_no_signal(1)
	_event_number.max_value = 1
	_source_label.text = str(input.fidelity) + "\n" + str(input.source)
	_apply_view()
	_show_status()


func step_once() -> void:
	if loading or dropped or frames >= int(input.hz) * 3: return
	var before := main.ball.global_position
	scenes.advance(main, input, frames)
	var motion := main.ball._motion as ViewMotion
	var cursor := before
	for saved: Dictionary in motion.events:
		var event := saved.duplicate(true)
		event["frame"] = frames + 1
		event["index_in_tick"] = motion.events.find(saved) + 1
		event["contacts_in_tick"] = motion.events.size()
		event["cap"] = motion.cap
		overlay.segments.append({"start": cursor, "end": _vec(event.correction_start), "correction": false})
		overlay.segments.append({"start": _vec(event.correction_start),
			"end": _vec(event.correction_end), "correction": true})
		cursor = _vec(event.correction_end)
		events.append(event)
		if event.correction_px > max_correction or _max_event < 0:
			max_correction = event.correction_px
			_max_event = events.size() - 1
	overlay.segments.append({"start": cursor, "end": main.ball.global_position, "correction": false})
	while overlay.segments.size() > 600: overlay.segments.pop_front()
	_positions.append(main.ball.global_position)
	capped_updates += int(motion.cap)
	frames += 1
	dropped = main.boundary.to_local(main.ball.global_position).y > main.boundary.bottom + 120
	if dropped or frames >= int(input.hz) * 3: playing = false
	_event_number.max_value = maxi(1, events.size())
	if (_track_max.button_pressed or _chosen < 0) and _max_event >= 0: select_contact(_max_event)
	_show_status()


func select_contact(index: int) -> void:
	if index < 0 or index >= events.size():
		_event_label.text = "接触前です。Nで1更新、または再生してください。"
		return
	_chosen = index
	_event_number.set_value_no_signal(index + 1)
	var event: Dictionary = events[index]
	overlay.event = event
	var other := "新規干渉なし（補正直後）"
	if event.has("environment"):
		var introduced: Array = event.environment.introduced
		if not introduced.is_empty():
			other = "新規干渉：" + ", ".join(introduced.map(func(row: Dictionary) -> String:
				return str(row.name) + " %.3f px" % row.get("depth_px", 0.0)))
		elif not event.environment.after.is_empty(): other = "補正後も周囲との接触あり"
		if event.environment.path_only: other += "\n補正経路で別物体を横切る候補"
	var direction := _vec(event.offset).normalized()
	_event_label.text = "更新%d・接触%d/%d：%s\n%s\n" % [event.frame,
		event.index_in_tick, event.contacts_in_tick, event.target, event.category]
	_event_label.text += "補正 %.3f px　向き (%.2f, %.2f)\n" % [event.correction_px, direction.x, direction.y]
	_event_label.text += "前 (%.2f, %.2f)\n後 (%.2f, %.2f)\n" % [event.correction_start[0],
		event.correction_start[1], event.correction_end[0], event.correction_end[1]]
	_event_label.text += "深さ %.3f px（%s）\n" % [event.depth_px, event.depth_kind]
	_event_label.text += "接触点 (%.2f, %.2f)\n法線 (%.3f, %.3f)\n" % [event.point[0],
		event.point[1], event.normal[0], event.normal[1]]
	_event_label.text += "速度 (%.1f, %.1f) px/s\n打球：%s　8接触到達：%s\n" % [event.velocity[0],
		event.velocity[1], "あり" if event.shot else "なし", "あり" if event.cap else "なし"]
	_event_label.text += other + "\n\n橙の円→緑の円：選択した補正\n赤：接触点と法線\n水色：実際の当たり四角形\n紫の輪郭：Enemyの当たり円\n白線：移動区間（補正を除く）"
	if not overlay.ghost.is_empty():
		_event_label.text += "\n灰線：前回%sの更新終了位置" % ["S" if _previous.mode == 0 else "B"]
	_event_label.text += "\n\n円・矢印は履歴の目印です。\n現在の球の位置とは別です。"
	if event.kind == "native":
		_event_label.text += "\n標準側の矢印は、safe fractionで\n移動分を除いた実効的な回復変位です。"
	overlay.queue_redraw()


func _physics_process(delta: float) -> void:
	if loading or not playing: return
	_accumulator += delta * speed
	var duration: float = 1.0 / input.hz
	if _accumulator + .000000001 >= duration:
		_accumulator -= duration
		step_once()


func _show_status() -> void:
	_play_button.text = "一時停止 P" if playing else "再生 P / Space"
	_play_button.disabled = dropped or frames >= int(input.hz) * 3
	var state := "落下位置へ到達（自動再生成なし）" if dropped else (
		"3秒終了・Rでリセット" if frames >= int(input.hz) * 3 else ("再生中" if playing else "一時停止"))
	_status.text = "%s　%d更新 / %.3f秒　%d Hz固定　接触%d　最大補正 %.3f px　8到達 %d更新" % [
		state, frames, float(frames) / input.hz, input.hz, events.size(), max_correction, capped_updates]
	if _chosen < 0: select_contact(-1)
	overlay.show_guides = _guides.button_pressed
	overlay.show_ghost = _ghost.button_pressed
	overlay.queue_redraw()


func _apply_view() -> void:
	if loading: return
	var zoom: float = [3.0, 2.0, 1.0, 1.0][_view_box.selected]
	var transform := Transform2D.IDENTITY.scaled(Vector2.ONE * zoom)
	if _view_box.selected != 3:
		transform.origin = Vector2(1270, 640) - _vec(input.focus) * zoom
	get_viewport().canvas_transform = transform
	overlay.zoom = zoom
	overlay.queue_redraw()


func _toggle_play() -> void:
	if loading or dropped or frames >= int(input.hz) * 3: return
	playing = not playing
	_accumulator = 0.0
	_show_status()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo: return
	match key.keycode:
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8:
			reset_case(key.keycode - KEY_1, mode)
		KEY_S: reset_case(scene_index, 0)
		KEY_B: reset_case(scene_index, 1)
		KEY_R: reset_case()
		KEY_P, KEY_SPACE: _toggle_play()
		KEY_N:
			playing = false
			step_once()
		KEY_V:
			_view_box.select(2 if _view_box.selected < 2 else (1 if scene_index in [1, 2] else 0))
			_apply_view()
		_: return
	get_viewport().set_input_as_handled()


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "Controls"
	layer.layer = 100
	add_child(layer)
	var header := _panel(layer, Vector2(18, 18), Vector2(1884, 0))
	var first := HBoxContainer.new()
	header.add_child(first)
	var title := Label.new()
	title.text = "位置補正の比較"
	title.add_theme_font_size_override("font_size", 25)
	first.add_child(title)
	_scene_box = OptionButton.new()
	_scene_box.custom_minimum_size.x = 470
	for row: Dictionary in scenes.cases: _scene_box.add_item(row.title)
	first.add_child(_scene_box)
	_scene_box.item_selected.connect(func(value: int) -> void: reset_case(value, mode))
	_mode_box = OptionButton.new()
	for text: String in MODES: _mode_box.add_item(text)
	first.add_child(_mode_box)
	_mode_box.item_selected.connect(func(value: int) -> void: reset_case(scene_index, value))
	_variant_box = OptionButton.new()
	_variant_box.add_item("ratio .5 / 旧深さ28.49")
	_variant_box.add_item("ratio .7 / 旧深さ40.59")
	first.add_child(_variant_box)
	_variant_box.item_selected.connect(func(value: int) -> void:
		variant = value
		_previous.clear()
		reset_case())
	var second := HBoxContainer.new()
	header.add_child(second)
	_play_button = _button(second, "再生 P / Space", _toggle_play)
	_button(second, "1更新 N", func() -> void:
		playing = false
		step_once())
	_button(second, "同じ初期状態 R", func() -> void: reset_case())
	var rate := OptionButton.new()
	rate.add_item("1/8速（物理条件固定）")
	rate.add_item("1/4速")
	rate.add_item("通常速度")
	second.add_child(rate)
	rate.item_selected.connect(func(value: int) -> void:
		speed = [.125, .25, 1.0][value]
		_accumulator = 0.0)
	_view_box = OptionButton.new()
	for text: String in ["拡大3×（接触中心）", "拡大2×（大補正の全体）",
		"原寸1×（接触中心）", "本番の盤面表示1×"]:
		_view_box.add_item(text)
	second.add_child(_view_box)
	_view_box.item_selected.connect(func(_value: int) -> void: _apply_view())
	_guides = _check(second, "補助線", true)
	_ghost = _check(second, "前回の残像", true)
	var details := _check(second, "詳細", true)
	_guides.toggled.connect(func(_value: bool) -> void:
		if not loading: _show_status())
	_ghost.toggled.connect(func(_value: bool) -> void:
		if not loading: _show_status())
	details.toggled.connect(func(value: bool) -> void: _details.visible = value)
	_source_label = Label.new()
	_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(_source_label)
	_status = Label.new()
	header.add_child(_status)
	var explanation := Label.new()
	explanation.text = "1〜8：場面　S / B：方式　V：倍率　3秒追跡。自動生成・ミサイル・自動再生成なし。補正を補間しません。"
	header.add_child(explanation)
	var body := _panel(layer, Vector2(18, 260), Vector2(450, 0))
	_details = body.get_parent() as PanelContainer
	_details.remove_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_details.add_child(scroll)
	scroll.add_child(body)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.custom_minimum_size.y = 790
	var history := HBoxContainer.new()
	body.add_child(history)
	var contact := Label.new()
	contact.text = "接触履歴"
	history.add_child(contact)
	_event_number = SpinBox.new()
	_event_number.min_value = 1
	_event_number.max_value = 1
	_event_number.step = 1
	history.add_child(_event_number)
	_event_number.value_changed.connect(func(value: float) -> void:
		_track_max.button_pressed = false
		select_contact(int(value) - 1))
	_track_max = _check(body, "最大補正を追跡", true)
	_track_max.toggled.connect(func(value: bool) -> void:
		if value: select_contact(_max_event))
	_event_label = Label.new()
	_event_label.custom_minimum_size.x = 420
	_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_event_label)


func _panel(parent: Node, position: Vector2, size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.position = position
	panel.custom_minimum_size = size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035, .045, .065, .94)
	style.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", style)
	var theme := Theme.new()
	theme.default_font_size = 20
	panel.theme = theme
	parent.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	panel.add_child(column)
	return column


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _check(parent: Node, text: String, pressed: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = pressed
	check.focus_mode = Control.FOCUS_NONE
	parent.add_child(check)
	return check


static func _vec(value: Array) -> Vector2:
	return Vector2(value[0], value[1])
