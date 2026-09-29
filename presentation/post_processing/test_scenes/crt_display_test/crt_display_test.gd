extends Node2D

const CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const DAMAGE_VALUES = [7, 42, 128, 999]

@onready var _post_processing: PostProcessing = $PostProcessing
@onready var _ui: Control = $WorldUILayer/UI
@onready var _damage_spawner: DamageNumberSpawner = $WorldUILayer/DamageNumberSpawner
@onready var _orb: Orb = $Orb
@onready var _enemy: Enemy = $Enemy
@onready var _enemy_target: Node2D = $EnemyTarget

var _effect: CRTDisplayExperimental
var _mode_label: Label
var _mode: int = 3
var _softness_mode: int = 3
var _base_mask_strength: float = 0.5
var _base_mipmap_strength: float = 0.08
var _base_horizontal_strength: float = 0.1
var _damage_elapsed: float = 0.0
var _damage_index: int = 0
var _motion_elapsed: float = 0.0


func _ready() -> void:
	_effect = _post_processing.composite_effects[0] as CRTDisplayExperimental
	_base_mask_strength = _effect.mask_strength
	_base_mipmap_strength = _effect.mipmap_strength
	_base_horizontal_strength = _effect.horizontal_strength
	_fit_canvas()
	get_viewport().size_changed.connect(_fit_canvas)
	_orb.position = Vector2(1515.0, 925.0)
	_enemy.position = Vector2(1770.0, 925.0)
	_enemy_target.position = Vector2(1760.0, 925.0)
	_enemy.movement.target = _enemy_target
	_enemy.set_physics_process(true)
	_create_labels()
	_set_mode(3)
	_set_softness_mode(3)
	_spawn_damage()


func _fit_canvas() -> void:
	var viewport_size := get_viewport_rect().size
	var canvas_scale := viewport_size / CANVAS_SIZE
	scale = canvas_scale
	$WorldUILayer.transform = Transform2D.IDENTITY.scaled(canvas_scale)


func _process(delta: float) -> void:
	_motion_elapsed += delta
	_orb.position = Vector2(
		1515.0 + 65.0 * sin(_motion_elapsed),
		925.0 + 16.0 * sin(_motion_elapsed * 1.8),
	)
	_enemy_target.position = Vector2(
		1760.0 + 100.0 * sin(_motion_elapsed * 0.9),
		925.0 + 28.0 * sin(_motion_elapsed * 1.3),
	)

	_damage_elapsed += delta
	if _damage_elapsed >= 1.2:
		_damage_elapsed -= 1.2
		_spawn_damage()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	match key.keycode:
		KEY_F1:
			_set_mode(0)
		KEY_F2:
			_set_mode(1)
		KEY_F3:
			_set_mode(2)
		KEY_F4:
			_set_mode(3)
		KEY_F5:
			_effect.mask_style = CRTDisplayExperimental.MaskStyle.VGA if (
				_effect.mask_style == CRTDisplayExperimental.MaskStyle.STRETCHED_VGA
			) else CRTDisplayExperimental.MaskStyle.STRETCHED_VGA
			_update_mode_label()
		KEY_F6:
			_set_softness_mode((_softness_mode + 1) % 4)
		KEY_SPACE:
			_spawn_damage()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, CANVAS_SIZE), Color(0.035, 0.04, 0.055))
	draw_rect(Rect2(0.0, 0.0, CANVAS_SIZE.x, 124.0), Color(0.018, 0.021, 0.03))
	_draw_checkerboard(Rect2(40.0, 165.0, 420.0, 260.0), 30.0)
	_draw_checkerboard(Rect2(480.0, 165.0, 420.0, 260.0), 3.0)
	_draw_grayscale_ramp(Rect2(920.0, 165.0, 460.0, 260.0))
	_draw_color_bars(Rect2(1400.0, 165.0, 480.0, 260.0))
	_draw_shapes()
	_draw_gradients()
	_draw_hdr_objects()
	_draw_fine_details()
	_draw_fine_grid(Rect2(480.0, 825.0, 420.0, 185.0))


func _create_labels() -> void:
	_add_label("CRT Display Experimental  |  virtual scanlines: 360", Vector2(40.0, 15.0), 28)
	_mode_label = _add_label("", Vector2(40.0, 62.0), 20, Color(0.8, 0.95, 1.0))
	_add_label("F1 OFF   F2 SIGNAL   F3 MASK   F4 BOTH   F5 MASK STYLE   F6 SOFTNESS   SPACE DAMAGE", Vector2(40.0, 91.0), 16)
	_add_label("COARSE CHECKER", Vector2(40.0, 135.0), 17)
	_add_label("FINE CHECKER / MOIRE", Vector2(480.0, 135.0), 17)
	_add_label("GRAYSCALE RAMP", Vector2(920.0, 135.0), 17)
	_add_label("RGB / CMY / WHITE", Vector2(1400.0, 135.0), 17)
	_add_label("SHAPES  |  2px to large", Vector2(40.0, 455.0), 17)
	_add_label("GRADIENTS", Vector2(920.0, 455.0), 17)
	_add_label("HDR  |  weak / medium / strong", Vector2(1400.0, 455.0), 17)
	_add_label("1px LINES / DIAGONALS / DOTS", Vector2(40.0, 790.0), 17)
	_add_label("FINE GRID", Vector2(480.0, 790.0), 17)
	_add_label("UI / TEXT", Vector2(920.0, 790.0), 17)
	_add_label("MOVING ORB / ENEMY / DAMAGE", Vector2(1400.0, 790.0), 17)
	_add_label("ORB", Vector2(1470.0, 990.0), 16, Color(0.6, 1.0, 0.6))
	_add_label("ENEMY", Vector2(1720.0, 990.0), 16, Color(0.5, 0.8, 1.0))
	_add_label("12px thin  012345  abcXYZ", Vector2(940.0, 830.0), 12)
	_add_label("18px normal  012345  abcXYZ", Vector2(940.0, 858.0), 18)
	_add_label("28px outline  012345", Vector2(940.0, 898.0), 28, Color.WHITE, 3)
	_add_label("42px LARGE  012345", Vector2(940.0, 945.0), 42)
	_add_label("R  G  B  cyan  magenta", Vector2(940.0, 1012.0), 16, Color(0.5, 0.9, 1.0))


func _add_label(
	label_text: String,
	label_position: Vector2,
	font_size: int,
	font_color: Color = Color(0.9, 0.92, 0.96),
	outline_size: int = 0,
) -> Label:
	var label := Label.new()
	label.text = label_text
	label.position = label_position
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	if outline_size > 0:
		label.add_theme_constant_override("outline_size", outline_size)
		label.add_theme_color_override("font_outline_color", Color(0.01, 0.015, 0.025))
	_ui.add_child(label)
	return label


func _set_mode(mode: int) -> void:
	_mode = mode
	_effect.enabled = mode != 0
	_effect.signal_enabled = mode == 1 or mode == 3
	_effect.mask_strength = 0.0 if mode == 1 else _base_mask_strength
	_update_mode_label()


func _set_softness_mode(mode: int) -> void:
	_softness_mode = mode
	_effect.mipmap_strength = _base_mipmap_strength if mode == 1 or mode == 3 else 0.0
	_effect.horizontal_strength = _base_horizontal_strength if mode == 2 or mode == 3 else 0.0
	_update_mode_label()


func _update_mode_label() -> void:
	var names := ["OFF", "SIGNAL / BEAM", "SHADOW MASK", "BOTH"]
	var softness_names := ["OFF", "MIPMAP", "HORIZONTAL", "BOTH"]
	var style := "VGA" if _effect.mask_style == CRTDisplayExperimental.MaskStyle.VGA else "Stretched VGA"
	_mode_label.text = "Mode: %s    Mask: %s    Softness: %s" % [names[_mode], style, softness_names[_softness_mode]]


func _spawn_damage() -> void:
	var damage := float(DAMAGE_VALUES[_damage_index])
	var spawn_position := Vector2(1600.0 + float(_damage_index) * 22.0, 1010.0)
	_damage_spawner.spawn(damage, Vector2.ZERO, spawn_position)
	_damage_index = (_damage_index + 1) % DAMAGE_VALUES.size()


func _draw_checkerboard(rect: Rect2, cell_size: float) -> void:
	var columns := int(ceil(rect.size.x / cell_size))
	var rows := int(ceil(rect.size.y / cell_size))
	for row in rows:
		for column in columns:
			var cell_position := rect.position + Vector2(column, row) * cell_size
			var cell_size_clipped := Vector2(
				minf(cell_size, rect.end.x - cell_position.x),
				minf(cell_size, rect.end.y - cell_position.y),
			)
			var color := Color(0.08, 0.1, 0.14) if (row + column) % 2 == 0 else Color(0.7, 0.72, 0.75)
			draw_rect(Rect2(cell_position, cell_size_clipped), color)


func _draw_grayscale_ramp(rect: Rect2) -> void:
	for column in int(rect.size.x):
		var level := float(column) / (rect.size.x - 1.0)
		draw_rect(Rect2(rect.position + Vector2(column, 0.0), Vector2(1.0, rect.size.y)), Color(level, level, level))


func _draw_color_bars(rect: Rect2) -> void:
	var colors: Array[Color] = [
		Color.RED, Color.GREEN, Color.BLUE, Color.CYAN, Color.MAGENTA, Color.YELLOW, Color.WHITE,
	]
	var bar_width := rect.size.x / float(colors.size())
	for index in colors.size():
		var left := rect.position.x + float(index) * bar_width
		var right := rect.position.x + float(index + 1) * bar_width
		draw_rect(Rect2(left, rect.position.y, right - left, rect.size.y), colors[index])


func _draw_shapes() -> void:
	draw_circle(Vector2(90.0, 620.0), 2.0, Color(0.75, 0.8, 0.9))
	draw_circle(Vector2(145.0, 620.0), 7.0, Color(0.07, 0.28, 0.7))
	draw_circle(Vector2(225.0, 620.0), 19.0, Color(0.85, 0.25, 0.15))
	draw_circle(Vector2(370.0, 620.0), 72.0, Color(0.8, 0.83, 0.88))
	draw_colored_polygon(
		PackedVector2Array([Vector2(530.0, 695.0), Vector2(610.0, 530.0), Vector2(690.0, 695.0)]),
		Color(0.25, 0.7, 0.35),
	)
	draw_rect(Rect2(735.0, 560.0, 110.0, 110.0), Color(0.5, 0.22, 0.65))
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(70.0, 745.0), Vector2(105.0, 710.0),
			Vector2(140.0, 745.0), Vector2(105.0, 780.0),
		]),
		Color(0.8, 0.7, 0.2),
	)
	draw_rect(Rect2(210.0, 725.0, 260.0, 5.0), Color(0.92, 0.92, 0.98))
	draw_rect(Rect2(500.0, 716.0, 4.0, 60.0), Color(0.9, 0.65, 0.5))
	var hexagon := PackedVector2Array()
	for index in 6:
		var angle := TAU * float(index) / 6.0
		hexagon.append(Vector2(660.0, 743.0) + Vector2.RIGHT.rotated(angle) * 38.0)
	draw_colored_polygon(hexagon, Color(0.26, 0.75, 0.78))


func _draw_gradients() -> void:
	for column in 420:
		var amount := float(column) / 419.0
		var dark_to_bright := Color(0.02, 0.03, 0.08).lerp(Color(0.95, 0.98, 1.0), amount)
		var saturated_to_white := Color(0.06, 0.18, 0.9).lerp(Color.WHITE, amount)
		draw_rect(Rect2(940.0 + column, 515.0, 1.0, 88.0), dark_to_bright)
		draw_rect(Rect2(940.0 + column, 625.0, 1.0, 88.0), saturated_to_white)
	for step in range(36, 0, -1):
		var amount := 1.0 - float(step) / 36.0
		var color := Color(0.75, 0.12, 0.2).lerp(Color(0.12, 0.85, 0.8), amount)
		draw_circle(Vector2(1145.0, 755.0), float(step) * 1.25, color)


func _draw_hdr_objects() -> void:
	draw_circle(Vector2(1505.0, 570.0), 45.0, Color(1.3, 0.35, 0.15))
	draw_circle(Vector2(1640.0, 570.0), 45.0, Color(0.4, 2.1, 0.8))
	draw_circle(Vector2(1775.0, 570.0), 45.0, Color(2.8, 2.4, 1.6))
	draw_rect(Rect2(1435.0, 660.0, 400.0, 85.0), Color(1.8, 0.6, 3.0))


func _draw_fine_details() -> void:
	draw_rect(Rect2(40.0, 825.0, 420.0, 185.0), Color(0.09, 0.1, 0.13))
	for index in 8:
		var offset := float(index) * 35.0
		draw_line(Vector2(60.0, 845.0 + offset * 0.5), Vector2(430.0, 845.0 + offset * 0.5), Color.WHITE, 1.0)
		draw_line(Vector2(60.0 + offset, 845.0), Vector2(60.0 + offset, 990.0), Color(0.3, 0.8, 1.0), 1.0)
	draw_line(Vector2(65.0, 985.0), Vector2(430.0, 850.0), Color(1.0, 0.45, 0.4), 1.0)
	for index in 24:
		var point := Vector2(
			75.0 + float(index % 12) * 25.0,
			880.0 + floor(float(index) / 12.0) * 45.0,
		)
		draw_rect(Rect2(point, Vector2.ONE), Color(0.95, 0.95, 0.95))


func _draw_fine_grid(rect: Rect2) -> void:
	draw_rect(rect, Color(0.1, 0.11, 0.14))
	for column in int(rect.size.x / 4.0):
		var x := rect.position.x + float(column) * 4.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0.8, 0.82, 0.86), 1.0)
	for row in int(rect.size.y / 4.0):
		var y := rect.position.y + float(row) * 4.0
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color(0.8, 0.82, 0.86), 1.0)
