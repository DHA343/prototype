extends Node2D

const PreviewBall = preload("res://experiments/flippers/preview_ball.gd")
const FixedFlipper = preload("res://experiments/flippers/fixed_flipper.gd")
const ShotGuard = preload("res://experiments/flippers/shot_guard.gd")
const STEP: float = 1.0 / 240.0
const RESPAWN_DELAY: float = 0.45

@export var show_controls: bool = true

var paused: bool = false
var balls: Array[PinballBall] = []
var auto_respawn: bool = true
var _spawn_position: Vector2
var _respawn_remaining: Dictionary[int, float] = {}
var _shot_velocity: Vector2 = Vector2.ZERO
var _pause_button: Button
var _status: Label
var _fields: Array[SpinBox] = []

@onready var ball: PinballBall = $Playfield/Ball
@onready var flippers: PinballFlippers = $Playfield/Flippers
@onready var boundary: PinballBoundary = $Playfield/Boundary


func _ready() -> void:
	ball.boundary = boundary
	ball.flippers = flippers
	balls.append(ball)
	_spawn_position = ball.global_position
	if show_controls:
		_build_controls()
	else:
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
	set_paused(false)


func _physics_process(delta: float) -> void:
	if not paused:
		advance(delta)
	_shot_velocity = predict_shot()
	queue_redraw()


func _process(_delta: float) -> void:
	var target := ball as PreviewBall
	_status.text = "停止中" if paused else "実行中"
	_status.text += "\n最大位置補正 %.2f px\n無効化：未導入（mainの抑制を継承）" % target.max_separation


func _draw() -> void:
	if _shot_velocity != Vector2.ZERO:
		var start := to_local(ball.global_position)
		draw_line(start, to_local(ball.global_position + _shot_velocity.normalized() * 270.0),
			Color(0.6, 0.8, 0.85), 3.0)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for field: SpinBox in _fields:
			if field.get_line_edit().has_focus() and not field.get_global_rect().has_point(event.position):
				field.apply()
				field.get_line_edit().release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_P:
			set_paused(not paused)
		elif event.keycode == KEY_N and paused:
			advance(1.0 / 60.0)
		elif event.keycode == KEY_R:
			reset_ball()


func advance(delta: float) -> void:
	advance_inputs(delta, Input.is_action_pressed(&"pinball_left"),
		Input.is_action_pressed(&"pinball_right"))


func advance_inputs(delta: float, left: bool, right: bool) -> void:
	var remaining := delta
	var smallest_radius := ball.radius
	for target: PinballBall in balls:
		smallest_radius = minf(smallest_radius, target.radius)
	while remaining > 0.000001:
		var step := minf(minf(STEP, remaining), flippers.motion_step_limit(smallest_radius, left, right))
		var swings := flippers.plan_motion(left, right)
		flippers.advance(step, left, right)
		for index in balls.size():
			var target := balls[index]
			var id := target.get_instance_id()
			if target.active:
				target.advance(step, swings)
				if boundary.to_local(target.global_position).y > boundary.bottom + 120.0:
					target.active = false
					target.visible = false
					_respawn_remaining[id] = RESPAWN_DELAY
					if flippers is ShotGuard:
						(flippers as ShotGuard).forget_ball(target)
			elif auto_respawn:
				_respawn_remaining[id] -= step
				if _respawn_remaining[id] <= 0.0:
					if balls.size() == 1:
						reset_ball()
					else:
						target.reset_at(_spawn_for(index))
						_respawn_remaining.erase(id)
		remaining -= step


func reset_ball() -> void:
	flippers.reset_input()
	for index in balls.size():
		balls[index].reset_at(_spawn_for(index))
	_respawn_remaining.clear()


func set_ball_count(count: int) -> void:
	assert(count >= 1 and count <= 50)
	while balls.size() > count:
		var removed: PinballBall = balls.pop_back()
		removed.free()
	while balls.size() < count:
		var added := ball.duplicate() as PinballBall
		added.name = "Ball%02d" % (balls.size() + 1)
		ball.get_parent().add_child(added)
		added.boundary = boundary
		added.flippers = flippers
		balls.append(added)
	reset_ball()


func _spawn_for(index: int) -> Vector2:
	if balls.size() == 1:
		return _spawn_position
	var columns := 5 if balls.size() <= 20 else 10
	return Vector2(620.0 + (index % columns) * 640.0 / (columns - 1),
		240.0 + (index / columns) * 120.0)


func predict_shot() -> Vector2:
	if not ball.active:
		return Vector2.ZERO
	if flippers is ShotGuard and (flippers as ShotGuard).is_suppressed(ball):
		return Vector2.ZERO
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = (ball.get_node("CollisionShape2D") as CollisionShape2D).shape
	query.collision_mask = ball.collision_mask
	var excluded: Array[RID] = [ball.get_rid()]
	for flipper: PinballFlipper in flippers.items:
		excluded.append(flipper.get_rid())
	query.exclude = excluded
	var space := ball.get_world_2d().direct_space_state
	var position := ball.global_position
	var velocity := ball.velocity
	var elapsed := 0.0
	var swings := flippers.plan_motion(true, true)
	var stationary := flippers.items.duplicate()
	for swing: PinballFlipper.Swing in swings:
		stationary.erase(swing.flipper)
	var horizon := deg_to_rad(flippers.swing_angle) / deg_to_rad(flippers.raise_speed)
	var step_limit := flippers.motion_step_limit(ball.radius, true, true)
	while elapsed < horizon:
		var step := minf(minf(STEP, step_limit), horizon - elapsed)
		velocity = ball.step_velocity(velocity, step)
		query.transform = Transform2D(0.0, position)
		query.motion = velocity * step
		var travel := space.cast_motion(query)
		var hit := flippers.first_contact(swings, position, velocity, ball.radius, elapsed, step * travel[0])
		if not hit.is_empty() and (travel[0] >= 1.0 or hit.time < step * travel[0]):
			var normal: Vector2 = hit.normal
			var surface_velocity: Vector2 = hit.surface_velocity
			if (velocity - surface_velocity).dot(normal) < 0.0:
				var reflected := PinballBall.reflected_velocity(velocity, normal,
					flippers.restitution, hit.strike_surface_velocity)
				if hit.is_striking:
					var flipper: PinballFlipper = hit.flipper
					reflected = flippers.direct_shot(reflected, hit.ratio, flipper.side, normal)
				return reflected.limit_length(ball.max_speed)
		# A wall or bumper reached first invalidates this direct flipper preview.
		if travel[0] < 1.0:
			return Vector2.ZERO
		position += query.motion
		elapsed += step
		for flipper: PinballFlipper in stationary:
			if not flipper.visible:
				continue
			var contact := flipper.predicted_contact(position, ball.radius, elapsed, step,
				flippers.swing_angle, flippers.raise_speed, flippers.power_equalization)
			if contact.is_empty():
				continue
			var normal: Vector2 = contact["normal"]
			var surface_velocity: Vector2 = contact["surface_velocity"]
			if (velocity - surface_velocity).dot(normal) < 0.0:
				surface_velocity = contact["strike_surface_velocity"]
				var reflected := PinballBall.reflected_velocity(velocity, normal,
					flippers.restitution, surface_velocity)
				if contact["is_striking"]:
					reflected = flippers.direct_shot(reflected, contact["ratio"], flipper.side, normal)
				return reflected.limit_length(ball.max_speed)
	return Vector2.ZERO


func set_paused(value: bool) -> void:
	paused = value
	if not show_controls:
		return
	_pause_button.text = "再開（P）" if paused else "一時停止（P）"
	for field: SpinBox in _fields:
		field.editable = paused


func _build_controls() -> void:
	var layer := CanvasLayer.new()
	layer.name = "PreviewControls"
	layer.layer = 100
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(1460.0, 24.0)
	panel.custom_minimum_size.x = 430.0
	layer.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_label(box, "フリッパー調整プレビュー")
	_label(box, "mainの壁・穴・球・フリッパー配置\n左右／下端固定・上向き補正\nA / D / Space：フリッパー専用\nP：停止再開　N：1更新　R：球を戻す")
	_spin(box, "追加の厚み px", 0.0, 240.0, 12.0, 48.0,
		func(value: float) -> void:
			for item: PinballFlipper in flippers.items:
				(item as FixedFlipper).extra_thickness = value)
	_spin(box, "球の半径 px", 6.0, 36.0, 1.0, ball.radius,
		func(value: float) -> void: ball.radius = value)
	_pause_button = Button.new()
	_pause_button.name = "Pause"
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.pressed.connect(func() -> void: set_paused(not paused))
	box.add_child(_pause_button)
	var reset := Button.new()
	reset.name = "Reset"
	reset.focus_mode = Control.FOCUS_NONE
	reset.text = "球を初期位置へ戻す（R）"
	reset.pressed.connect(reset_ball)
	box.add_child(reset)
	_status = _label(box, "")


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 19)
	parent.add_child(label)
	return label


func _spin(
	parent: Node, title: String, low: float, high: float, step: float, initial: float, changed: Callable,
) -> void:
	_label(parent, title)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = initial
	parent.add_child(spin)
	_fields.append(spin)
	spin.value_changed.connect(changed)
	spin.get_line_edit().text_submitted.connect(func(_text: String) -> void:
		spin.apply()
		spin.get_line_edit().release_focus.call_deferred())

