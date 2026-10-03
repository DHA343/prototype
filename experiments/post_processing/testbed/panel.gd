extends PanelContainer

var testbed: Node2D
var _catalog: Array = []
var _category: OptionButton
var _stage: OptionButton
var _stack: ItemList
var _controls: VBoxContainer
var _status: Label
var _selected: int = -1
var _modes: Dictionary[ExperimentEffect, int] = {}
var _dialog: FileDialog
var _file_action: String
var _file_effect: ExperimentEffect
var _file_parameter: StringName

@onready var _post: PostProcessing = testbed.get_node("PostProcessing")


func _ready() -> void:
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://experiments/post_processing/catalog.json"))
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -390.0
	offset_right = -12.0
	offset_top = 12.0
	offset_bottom = -12.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.045, 0.06, 0.98)
	add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	var sources := HBoxContainer.new()
	column.add_child(sources)
	_button(sources, "1 Main", testbed.select_source.bind(0))
	_button(sources, "2 Pattern", testbed.select_source.bind(1))
	_button(sources, "3 Image", testbed.next_image)
	_button(column, "Open image (Ctrl+O)", open_file.bind("image"))
	var master := CheckBox.new()
	master.text = "Effects enabled"
	master.button_pressed = _post.enabled
	master.toggled.connect(func(value: bool) -> void: _post.enabled = value)
	column.add_child(master)
	_category = OptionButton.new()
	for entry: Dictionary in _catalog:
		_category.add_item(String(entry.title))
	column.add_child(_category)
	_button(column, "Add effect", add_effect)
	_stage = OptionButton.new()
	_stage.add_item("Composite (including text / UI)")
	_stage.add_item("World (before text / UI)")
	_stage.item_selected.connect(_stage_changed)
	column.add_child(_stage)
	_stack = ItemList.new()
	_stack.custom_minimum_size.y = 105.0
	_stack.item_selected.connect(_select_effect)
	column.add_child(_stack)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_button(actions, "Up", move_effect.bind(-1))
	_button(actions, "Down", move_effect.bind(1))
	_button(actions, "Remove", remove_effect)
	_button(actions, "Reset", reset_effect)
	var presets := HBoxContainer.new()
	column.add_child(presets)
	_button(presets, "Save preset", open_file.bind("save"))
	_button(presets, "Load preset", open_file.bind("load"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_controls = VBoxContainer.new()
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls)
	_dialog = FileDialog.new()
	_dialog.file_selected.connect(_file_selected)
	add_child(_dialog)
	_watch_effects()
	_refresh_stack()


func set_status(text: String) -> void:
	_status.text = text


func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)


func effects() -> Array[PostProcessEffect]:
	return _post.composite_effects if _stage.selected == 0 else _post.world_effects


func add_effect() -> void:
	var entry: Dictionary = _catalog[_category.selected]
	var script := load(String(entry.script)) as Script
	var effect := script.new() as PostProcessEffect
	effect.resource_local_to_scene = true
	effects().append(effect)
	_selected = effects().size() - 1
	apply_stack()


func move_effect(direction: int) -> void:
	var next := _selected + direction
	if _selected < 0 or next < 0 or next >= effects().size():
		return
	var effect := effects()[_selected]
	effects().remove_at(_selected)
	effects().insert(next, effect)
	_selected = next
	apply_stack()


func remove_effect() -> void:
	if _selected < 0:
		return
	effects().remove_at(_selected)
	_selected = mini(_selected, effects().size() - 1)
	apply_stack()


func reset_effect() -> void:
	if _selected < 0:
		return
	var script: Script = effects()[_selected].get_script()
	effects()[_selected] = script.new() as PostProcessEffect
	apply_stack()


func apply_stack() -> void:
	_watch_effects()
	_post.rebuild_effects()
	_refresh_stack()


func _watch_effects() -> void:
	for effect in _post.world_effects + _post.composite_effects:
		if effect is ExperimentEffect:
			var experiment := effect as ExperimentEffect
			if not _modes.has(experiment):
				_modes[experiment] = int(experiment.get_parameter(&"mode"))
				experiment.changed.connect(_mode_changed.bind(experiment), CONNECT_DEFERRED)
	for experiment: ExperimentEffect in _modes.keys():
		if not _post.world_effects.has(experiment) and not _post.composite_effects.has(experiment):
			experiment.changed.disconnect(_mode_changed.bind(experiment))
			_modes.erase(experiment)


func _mode_changed(effect: ExperimentEffect) -> void:
	if not _modes.has(effect):
		return
	var mode := int(effect.get_parameter(&"mode"))
	if _modes[effect] != mode:
		_modes[effect] = mode
		_post.rebuild_effects()


func _stage_changed(_index: int) -> void:
	_selected = -1
	_refresh_stack()


func _select_effect(index: int) -> void:
	_selected = index
	_populate_controls()


func _refresh_stack() -> void:
	_stack.clear()
	for effect in effects():
		_stack.add_item(effect.get_script().resource_path.get_file().get_basename())
	if _selected >= 0 and _selected < effects().size():
		_stack.select(_selected)
	_populate_controls()


func _populate_controls() -> void:
	for child in _controls.get_children():
		_controls.remove_child(child)
		child.queue_free()
	if _selected < 0 or _selected >= effects().size():
		return
	var effect := effects()[_selected]
	var toggle := CheckBox.new()
	toggle.text = "Effect enabled"
	toggle.button_pressed = effect.enabled
	toggle.toggled.connect(func(value: bool) -> void: effect.enabled = value)
	_controls.add_child(toggle)
	for property: Dictionary in effect.get_property_list():
		var name := StringName(property.name)
		var value: Variant
		if effect is ExperimentEffect:
			if not String(name).begins_with("settings/"):
				continue
			name = StringName(String(name).trim_prefix("settings/"))
			value = (effect as ExperimentEffect).get_parameter(name)
		else:
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0 or property.usage & PROPERTY_USAGE_EDITOR == 0 or name == &"enabled":
				continue
			value = effect.get(name)
		var label := Label.new()
		label.text = String(name).capitalize()
		_controls.add_child(label)
		if property.hint == PROPERTY_HINT_ENUM:
			var option := OptionButton.new()
			for choice in String(property.hint_string).split(","):
				var pair := choice.split(":")
				option.add_item(pair[0], int(pair[1]) if pair.size() > 1 else option.item_count)
			option.select(option.get_item_index(int(value)))
			option.item_selected.connect(func(index: int) -> void: _set_value(effect, name, option.get_item_id(index)))
			_controls.add_child(option)
		elif value is bool:
			var check := CheckBox.new()
			check.button_pressed = bool(value)
			check.toggled.connect(func(v: bool) -> void: _set_value(effect, name, v))
			_controls.add_child(check)
		elif value is float or value is int:
			var spin := _number(property, float(value))
			spin.value_changed.connect(func(v: float) -> void: _set_value(effect, name, int(v) if property.type == TYPE_INT else v))
			_controls.add_child(spin)
		elif value is Color:
			var picker := ColorPickerButton.new()
			picker.color = value
			picker.color_changed.connect(func(v: Color) -> void: _set_value(effect, name, v))
			_controls.add_child(picker)
		elif value is Vector2 or value is Vector3:
			var row := HBoxContainer.new()
			_controls.add_child(row)
			for axis in (2 if value is Vector2 else 3):
				var spin := _number(property, float(value[axis]))
				spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				spin.value_changed.connect(func(v: float) -> void:
					var updated: Variant = (effect as ExperimentEffect).get_parameter(name) if effect is ExperimentEffect else effect.get(name)
					updated[axis] = v
					_set_value(effect, name, updated))
				row.add_child(spin)
		elif effect is ExperimentEffect and property.type == TYPE_OBJECT:
			_button(_controls, "Load texture", _open_texture.bind(effect, name))
			_button(_controls, "Clear texture", _set_value.bind(effect, name, null))


func _number(property: Dictionary, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = -100.0
	spin.max_value = 100.0
	spin.step = 0.01
	if property.hint == PROPERTY_HINT_RANGE:
		var parts: PackedStringArray = String(property.hint_string).split(",")
		spin.min_value = float(parts[0])
		spin.max_value = float(parts[1])
		if parts.size() > 2:
			spin.step = float(parts[2])
	elif property.type == TYPE_INT:
		spin.step = 1.0
	spin.value = value
	return spin


func _set_value(effect: PostProcessEffect, name: StringName, value: Variant) -> void:
	if effect is ExperimentEffect:
		(effect as ExperimentEffect).set_parameter(name, value)
	else:
		effect.set(name, value)


func _open_texture(effect: ExperimentEffect, parameter: StringName) -> void:
	_file_effect = effect
	_file_parameter = parameter
	open_file("texture")


func open_file(action: String) -> void:
	_file_action = action
	_dialog.access = FileDialog.ACCESS_FILESYSTEM if action in ["image", "texture"] else FileDialog.ACCESS_USERDATA
	_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if action == "save" else FileDialog.FILE_MODE_OPEN_FILE
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.bmp;Images"]) if action in ["image", "texture"] else PackedStringArray(["*.tres;Post-process preset"])
	if action == "save":
		_dialog.current_file = "post_process_preset.tres"
	_dialog.popup_centered(Vector2i(800, 600))


func _file_selected(path: String) -> void:
	if _file_action in ["image", "texture"]:
		var image := Image.load_from_file(path)
		if image == null:
			set_status("Could not load image.")
			return
		var texture := ImageTexture.create_from_image(image)
		if _file_action == "texture":
			_file_effect.set_parameter(_file_parameter, texture)
		else:
			var images: Array[Texture2D] = testbed.get("images")
			images.append(texture)
			var pattern: Node2D = testbed.get("_pattern")
			pattern.set("images", images)
			pattern.set("_image_index", images.size() - 1)
			pattern.queue_redraw()
			testbed.select_source(2)
	elif _file_action == "save":
		var preset := PostProcessPreset.new()
		preset.world_effects = _post.world_effects
		preset.composite_effects = _post.composite_effects
		set_status("Preset saved." if ResourceSaver.save(preset, path) == OK else "Could not save preset.")
	else:
		var preset := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as PostProcessPreset
		if preset == null:
			set_status("Not a post-process preset.")
			return
		_post.world_effects = preset.world_effects
		_post.composite_effects = preset.composite_effects
		_selected = -1
		_watch_effects()
		_refresh_stack()
