extends Node2D

const MembraneEffect = preload("res://tests/edge_membrane/membrane.gd")
const DIRECTIONS: Array[Vector2] = [
	Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1.0, -1.0)
]

var _is_demo: bool = false
var _demo_time: float = 0.0
var _demo_index: int = 0
var _demo_speed: float = 800.0
var _feedback: Feedback = Feedback.new()
var _status: Label

@onready var _orb: Orb = $Actors/Orb
@onready var _membrane: MembraneEffect = $Distortion/Membrane
@onready var _controls: VBoxContainer = $Interface/Panel/Margin/Controls


func _ready() -> void:
	_orb.setup(_feedback)
	_orb.set_physics_process(not _is_demo)
	_orb.orb_input.set_process_unhandled_input(not _is_demo)
	_build_controls()
	_membrane.reset()
	_update_status()


func _process(delta: float) -> void:
	if not _is_demo:
		return
	_demo_time += delta
	var viewport_size := get_viewport_rect().size
	var direction := (DIRECTIONS[_demo_index] * viewport_size).normalized()
	var travel := viewport_size * 0.5 + Vector2.ONE * 110.0
	var distance := minf(travel.x / maxf(absf(direction.x), 0.001),
		travel.y / maxf(absf(direction.y), 0.001))
	var duration := distance / _demo_speed
	_set_orb_position(viewport_size * 0.5 + direction * minf(_demo_time, duration) * _demo_speed)
	if _demo_time > duration + 2.0:
		_demo_index = (_demo_index + 1) % DIRECTIONS.size()
		_restart()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey:
		match event.physical_keycode:
			KEY_SPACE:
				_is_demo = not _is_demo
				_orb.set_physics_process(not _is_demo)
				_orb.orb_input.set_process_unhandled_input(not _is_demo)
				_orb.set_brake_pressed(false)
				_restart()
			KEY_R:
				_restart()
			KEY_E:
				_membrane.visible = not _membrane.visible
			KEY_H:
				_controls.get_parent().get_parent().visible = not _controls.get_parent().get_parent().visible
	_update_status()


func _restart() -> void:
	_demo_time = 0.0
	_orb.movement.clear()
	_set_orb_position(get_viewport_rect().size * 0.5)
	_membrane.reset()
	_update_status()


func _set_orb_position(point: Vector2) -> void:
	_orb.position = point + Vector2(0.0, _orb.radius)
	_orb.reset_position_interpolation()


func _update_status() -> void:
	var mode := "自動デモ" if _is_demo else "マウス操作"
	var effect := "ON" if _membrane.visible else "OFF"
	_status.text = "画面端の水面 / %s / 波 %s" % [mode, effect]


func _build_controls() -> void:
	_status = Label.new()
	_controls.add_child(_status)
	var help := Label.new()
	help.text = "Space: 操作切替  R: 中央へ戻す  E: 歪み比較  H: パネル表示\nマウス操作: 左クリックでブースト / 右クリックでブレーキ"
	_controls.add_child(help)
	_add_slider("波の強さ", &"strength", 0.0, 100.0, 1.0)
	_add_slider("基準速度", &"reference_speed", 400.0, 4000.0, 100.0)
	_add_slider("強度の上限倍率", &"max_multiplier", 1.0, 3.0, 0.1)
	_add_slider("斜め方向への流れ", &"directional_flow", 0.0, 1.0, 0.05)
	_add_slider("縁に沿う広さ", &"spread", 40.0, 400.0, 5.0)
	_add_slider("水面の帯幅", &"depth", 40.0, 240.0, 5.0)
	_add_slider("波の間隔", &"wavelength", 40.0, 160.0, 5.0)
	_add_slider("接近の反応距離", &"approach", 40.0, 320.0, 5.0)
	_add_slider("揺れる速さ", &"frequency", 0.5, 5.0, 0.1)
	_add_slider("減衰（小さいほど長く揺れる）", &"damping", 0.1, 0.9, 0.05)
	_add_slider("デモ速度", &"_demo_speed", 200.0, 6000.0, 100.0, self)


func _add_slider(
	caption: String,
	property: StringName,
	minimum: float,
	maximum: float,
	step: float,
	subject: Object = null
) -> void:
	if subject == null:
		subject = _membrane
	var row := HBoxContainer.new()
	_controls.add_child(row)
	var label := Label.new()
	label.custom_minimum_size.x = 310.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.custom_minimum_size.x = 200.0
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(subject.get(property))
	slider.focus_mode = Control.FOCUS_NONE
	row.add_child(slider)
	label.text = "%s: %.2f" % [caption, slider.value]
	slider.value_changed.connect(func(value: float) -> void:
		subject.set(property, value)
		label.text = "%s: %.2f" % [caption, value]
	)
