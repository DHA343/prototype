extends Control

const PIXEL_VIEW: Script = preload("./mask_pixels.gd")
const INPUT_SHADER: Shader = preload("./mask_input.gdshader")
const TEST_SCENE_PATH: String = "res://presentation/post_processing/test_scenes/crt_display_test/crt_display_test.tscn"
const SAMPLE_SIZE: Vector2i = Vector2i(32, 24)
const PATTERN_NAMES: Array[String] = [
	"RGB Rows", "RGB Row Pairs",
	"RGB Pixel Pattern", "Green / Magenta Stripes",
]

var _effect: CRTDisplayExperimental
var _input_material: ShaderMaterial
var _core_material: ShaderMaterial
var _cell_material: ShaderMaterial
var _input_viewport: SubViewport
var _output_viewport: SubViewport
var _cell_copy: BackBufferCopy
var _cell_rect: ColorRect
var _input_view: PIXEL_VIEW
var _output_view: PIXEL_VIEW
var _probe: Label
var _preview_scroll: ScrollContainer
var _fit_button: CheckButton
var _controls: Dictionary[StringName, Control] = {}
var _input_image: Image
var _output_image: Image
var _selected_pixel: Vector2i = Vector2i.ZERO
var _readback_pending: bool = false
var _window: Window
var _previous_content_scale_mode: int


func _ready() -> void:
	_window = get_window()
	_previous_content_scale_mode = _window.content_scale_mode
	_window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_viewport().use_hdr_2d = true
	_effect = _load_mask()
	# Isolate the mask while keeping the current test's saved mask settings.
	_effect.signal_enabled = false
	_effect.scanline_strength = 0.0
	_create_renderers()
	_create_ui()
	_refresh()


func _exit_tree() -> void:
	_window.content_scale_mode = _previous_content_scale_mode as Window.ContentScaleMode


func _load_mask() -> CRTDisplayExperimental:
	var scene := ResourceLoader.load(
		TEST_SCENE_PATH, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE,
	) as PackedScene
	var state := scene.get_state()
	for node_index: int in range(state.get_node_count()):
		for property_index: int in range(state.get_node_property_count(node_index)):
			if state.get_node_property_name(node_index, property_index) != "composite_effects":
				continue
			var effects: Array = state.get_node_property_value(node_index, property_index)
			for effect: Resource in effects:
				if effect is CRTDisplayExperimental:
					return effect.duplicate() as CRTDisplayExperimental
	assert(false, "CRT test has no mask resource.")
	return null


func _create_renderers() -> void:
	_input_material = ShaderMaterial.new()
	_input_material.shader = INPUT_SHADER
	_input_viewport = _create_viewport("Input")
	_add_rect(_input_viewport, _input_material)
	_output_viewport = _create_viewport("Output")
	_add_rect(_output_viewport, _input_material)
	var core_copy := BackBufferCopy.new()
	core_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_output_viewport.add_child(core_copy)
	_core_material = ShaderMaterial.new()
	_core_material.shader = _effect.get_pass_shader(0)
	_add_rect(_output_viewport, _core_material)
	_cell_copy = BackBufferCopy.new()
	_cell_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	_output_viewport.add_child(_cell_copy)
	_cell_material = ShaderMaterial.new()
	_cell_material.shader = _effect.get_pass_shader(1)
	_cell_rect = _add_rect(_output_viewport, _cell_material)


func _create_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = SAMPLE_SIZE
	viewport.use_hdr_2d = true
	viewport.disable_3d = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	return viewport


func _add_rect(viewport: SubViewport, shader_material: ShaderMaterial) -> ColorRect:
	var rect := ColorRect.new()
	rect.size = Vector2(SAMPLE_SIZE)
	rect.material = shader_material
	viewport.add_child(rect)
	return rect


func _create_ui() -> void:
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	margin.add_child(content)
	var heading := Label.new()
	heading.text = "Mask Pixel Preview"
	heading.add_theme_font_size_override("font_size", 22)
	content.add_child(heading)
	var scope := Label.new()
	scope.text = "Mask単体 · 32×24出力pixel · 最近傍拡大 · Signal / Scanline / Spread / Bloom / Noiseなし"
	content.add_child(scope)
	var fields := GridContainer.new()
	fields.columns = 6
	fields.add_theme_constant_override("h_separation", 12)
	fields.add_theme_constant_override("v_separation", 8)
	content.add_child(fields)
	var model := _add_picker(fields, &"mask_model", "Mask Model", [
		"Mask Redistribution", "Cell Emission",
	])
	model.select(_effect.mask_model)
	model.item_selected.connect(_on_model_selected)
	var pattern := OptionButton.new()
	_add_field(fields, &"mask_pattern", "Mask Pattern", pattern)
	_refresh_patterns()
	pattern.item_selected.connect(_on_pattern_selected)
	var row_offset := _add_picker(fields, &"row_offset_mode", "段のずれ", [
		"ずれなし", "半周期", "整数pxの半周期",
	])
	row_offset.select(_effect.row_offset_mode)
	row_offset.item_selected.connect(_on_row_offset_selected)
	row_offset.tooltip_text = "毎段／2段ごとのずれ幅。整数版は半周期を切り捨てます。Pitch 3なら1px、半周期は1.5px。素子境界自体は丸めません。"
	_add_spin(fields, &"triad_pitch", "Triad Pitch · px", _effect.triad_pitch, 2, 6, 1)
	_add_spin(fields, &"row_pitch", "Row Pitch · px", _effect.row_pitch, 1, 4, 1)
	var sampling := _add_picker(fields, &"cell_sampling", "Cell Sampling", ["Horizontal 4", "2×2"])
	sampling.set_item_id(0, 1)
	sampling.set_item_id(1, 2)
	sampling.select(sampling.get_item_index(_effect.cell_sampling))
	sampling.item_selected.connect(_on_sampling_selected)
	_add_spin(fields, &"mask_strength", "Mask Strength", _effect.mask_strength, 0, 1, 0.01)
	_add_spin(fields, &"horizontal_gap", "Horizontal Gap · px", _effect.horizontal_gap, 0, 1, 0.05)
	_add_spin(fields, &"vertical_gap", "Vertical Gap · px", _effect.vertical_gap, 0, 1, 0.05)
	_add_spin(fields, &"brightness_compensation", "Brightness", _effect.brightness_compensation, 0.25, 6, 0.01)
	var input := _add_picker(fields, &"input_kind", "テスト画像", [
		"均一なグレー", "縦の境界", "1px水平線", "1px垂直線", "RGBの帯", "グラデーション",
	])
	input.item_selected.connect(_on_input_selected)
	input.tooltip_text = "Maskをかける前の画像。均一なグレーで配置を、細線や境界で色の分離・混ざり方を確認します。"
	_add_spin(fields, &"input_level", "入力強度 · linear RGB", 0.2, 0, 2, 0.01)
	var view_controls := HBoxContainer.new()
	view_controls.add_theme_constant_override("separation", 16)
	content.add_child(view_controls)
	var grid := CheckButton.new()
	grid.text = "pixel格子"
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	grid.button_pressed = true
	grid.toggled.connect(_on_grid_toggled)
	view_controls.add_child(grid)
	_fit_button = CheckButton.new()
	_fit_button.text = "幅に合わせる"
	_fit_button.button_pressed = true
	_fit_button.toggled.connect(_on_fit_toggled)
	view_controls.add_child(_fit_button)
	var zoom_label := Label.new()
	zoom_label.text = "表示倍率"
	view_controls.add_child(zoom_label)
	var zoom := SpinBox.new()
	zoom.min_value = 4
	zoom.max_value = 64
	zoom.step = 1
	zoom.value = 12
	zoom.editable = false
	zoom.value_changed.connect(_on_number_changed.bind(&"zoom"))
	view_controls.add_child(zoom)
	_controls[&"zoom"] = zoom
	_preview_scroll = ScrollContainer.new()
	_preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_scroll.resized.connect(_fit_width.call_deferred)
	content.add_child(_preview_scroll)
	var previews := HBoxContainer.new()
	previews.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	previews.add_theme_constant_override("separation", 24)
	_preview_scroll.add_child(previews)
	_input_view = _add_preview(previews, "Mask前（テスト画像）", _input_viewport.get_texture())
	_output_view = _add_preview(previews, "Mask後（出力）", _output_viewport.get_texture())
	_probe = Label.new()
	_probe.text = "pixelを指すか、クリック後に矢印キーで選択 · RGB値はlinear HDR"
	content.add_child(_probe)
	var note := Label.new()
	note.text = "画面ではRGB > 1が飽和します。Redistributionは入力強度1で均一な白へ近づくため、初期入力は0.2です。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	_fit_width.call_deferred()


func _add_field(fields: GridContainer, key: StringName, title: String, control: Control) -> void:
	var field := VBoxContainer.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields.add_child(field)
	var label := Label.new()
	label.text = title
	field.add_child(label)
	field.add_child(control)
	_controls[key] = control


func _add_picker(
	fields: GridContainer, key: StringName, title: String, options: Array[String],
) -> OptionButton:
	var picker := OptionButton.new()
	for option: String in options:
		picker.add_item(option)
	_add_field(fields, key, title, picker)
	return picker


func _add_spin(
	fields: GridContainer, key: StringName, title: String,
	initial: float, minimum: float, maximum: float, increment: float,
) -> void:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = increment
	spin.value = initial
	_add_field(fields, key, title, spin)
	spin.value_changed.connect(_on_number_changed.bind(key))


func _add_preview(parent: HBoxContainer, title: String, texture: Texture2D) -> PIXEL_VIEW:
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var label := Label.new()
	label.text = title
	panel.add_child(label)
	var pixels: PIXEL_VIEW = PIXEL_VIEW.new()
	pixels.texture = texture
	pixels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pixels.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	pixels.pixel_selected.connect(_on_pixel_selected)
	panel.add_child(pixels)
	var native_row := HBoxContainer.new()
	panel.add_child(native_row)
	var native_label := Label.new()
	native_label.text = "等倍（1:1）"
	native_row.add_child(native_label)
	var native := TextureRect.new()
	native.texture = texture
	native.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	native.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	native_row.add_child(native)
	return pixels


func _refresh_patterns() -> void:
	var picker := _controls[&"mask_pattern"] as OptionButton
	picker.clear()
	var count := 2 if _effect.mask_model == CRTDisplayExperimental.MaskModel.CELL_EMISSION else 4
	for index: int in range(count):
		picker.add_item(PATTERN_NAMES[index], index)
	picker.select(picker.get_item_index(_effect.mask_pattern))


func _refresh() -> void:
	_effect.apply_to_pass(_core_material, 0)
	_effect.apply_to_pass(_cell_material, 1)
	var cell_enabled := _effect.is_pass_enabled(1)
	_cell_copy.visible = cell_enabled
	_cell_rect.visible = cell_enabled
	var rgb_layout := _effect.mask_pattern in [0, 1]
	(_controls[&"triad_pitch"] as SpinBox).editable = rgb_layout
	(_controls[&"row_pitch"] as SpinBox).editable = rgb_layout
	(_controls[&"row_offset_mode"] as OptionButton).disabled = not rgb_layout
	(_controls[&"cell_sampling"] as OptionButton).disabled = not cell_enabled
	(_controls[&"horizontal_gap"] as SpinBox).editable = cell_enabled
	(_controls[&"vertical_gap"] as SpinBox).editable = cell_enabled
	if not _readback_pending:
		_readback_pending = true
		_read_pixels.call_deferred()


func _on_model_selected(index: int) -> void:
	_effect.mask_model = index
	_refresh_patterns()
	_refresh()


func _on_pattern_selected(index: int) -> void:
	_effect.mask_pattern = (_controls[&"mask_pattern"] as OptionButton).get_item_id(index)
	_refresh()


func _on_row_offset_selected(index: int) -> void:
	_effect.row_offset_mode = index
	_refresh()


func _on_sampling_selected(index: int) -> void:
	_effect.cell_sampling = (_controls[&"cell_sampling"] as OptionButton).get_item_id(index)
	_refresh()


func _on_input_selected(index: int) -> void:
	_input_material.set_shader_parameter(&"input_kind", index)
	_refresh()


func _on_number_changed(value: float, key: StringName) -> void:
	if key == &"zoom":
		_set_zoom(int(value))
		return
	if key == &"input_level":
		_input_material.set_shader_parameter(key, value)
	elif key in [&"triad_pitch", &"row_pitch"]:
		_effect.set(key, int(value))
	else:
		_effect.set(key, value)
	_refresh()


func _set_zoom(value: int) -> void:
	_input_view.zoom = value
	_output_view.zoom = value
	_input_view.update_size()
	_output_view.update_size()


func _on_fit_toggled(enabled: bool) -> void:
	(_controls[&"zoom"] as SpinBox).editable = not enabled
	if enabled:
		_fit_width()


func _fit_width() -> void:
	if _input_view == null or not _fit_button.button_pressed:
		return
	# Reserve the scrollbar's width so its appearance cannot alternate the zoom level.
	var scrollbar_width := _preview_scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var available_width := _preview_scroll.size.x - scrollbar_width - 24.0
	var zoom := clampi(floori(available_width / (2.0 * float(SAMPLE_SIZE.x))), 4, 64)
	(_controls[&"zoom"] as SpinBox).set_value_no_signal(float(zoom))
	_set_zoom(zoom)


func _on_grid_toggled(enabled: bool) -> void:
	_input_view.grid_enabled = enabled
	_output_view.grid_enabled = enabled
	_input_view.queue_redraw()
	_output_view.queue_redraw()


func _on_pixel_selected(pixel: Vector2i) -> void:
	_selected_pixel = pixel
	_input_view.selected_pixel = pixel
	_output_view.selected_pixel = pixel
	_input_view.queue_redraw()
	_output_view.queue_redraw()
	_update_probe()


func _read_pixels() -> void:
	# Read after the parameter changes have reached both screen-texture passes.
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_input_image = _input_viewport.get_texture().get_image()
	_output_image = _output_viewport.get_texture().get_image()
	_readback_pending = false
	_update_probe()


func _update_probe() -> void:
	if _input_image == null or _output_image == null:
		return
	var before := _input_image.get_pixelv(_selected_pixel)
	var after := _output_image.get_pixelv(_selected_pixel)
	_probe.text = "pixel (%d, %d) · linear HDR RGB\n入力  R %.4f   G %.4f   B %.4f     →     Mask後  R %.4f   G %.4f   B %.4f" % [
		_selected_pixel.x, _selected_pixel.y,
		before.r, before.g, before.b, after.r, after.g, after.b,
	]
