@tool
class_name PostProcessing
extends Node

@export var enabled: bool = true:
	set(value):
		if enabled == value:
			return

		enabled = value
		_apply_enabled_state()

@export var world_effects: Array[PostProcessEffect] = []:
	set(value):
		world_effects = value

		if _is_initialized:
			rebuild_effects()

@export var composite_effects: Array[PostProcessEffect] = []:
	set(value):
		composite_effects = value

		if _is_initialized:
			rebuild_effects()

var _is_initialized: bool = false
var _effect_bindings: Array[EffectBinding] = []
var _generated_layers: Array[CanvasLayer] = []


func _ready() -> void:
	_is_initialized = true
	rebuild_effects()


func _exit_tree() -> void:
	_disconnect_effects()
	_clear_generated_layers(true)
	_is_initialized = false


func rebuild_effects() -> void:
	_disconnect_effects()
	_clear_generated_layers()

	var registered_effects: Dictionary[int, bool] = {}

	_build_effect_layer(&"WorldEffects", RenderLayers.WORLD_EFFECTS, world_effects, registered_effects)
	_build_effect_layer(
		&"CompositeEffects",
		RenderLayers.COMPOSITE_EFFECTS,
		composite_effects,
		registered_effects,
	)

	_apply_enabled_state()


func _on_effect_changed(binding: EffectBinding) -> void:
	if not _effect_bindings.has(binding):
		return

	if (
		not is_instance_valid(binding.back_buffer_copy)
		or not is_instance_valid(binding.rect)
		or not is_instance_valid(binding.material)
	):
		return

	_set_binding_enabled(binding, binding.effect.enabled)
	binding.effect.apply_to(binding.material)


func _build_effect_layer(
	layer_name: StringName,
	layer_index: int,
	effects: Array[PostProcessEffect],
	registered_effects: Dictionary[int, bool],
) -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = layer_name
	canvas_layer.layer = layer_index
	add_child(canvas_layer, false, Node.INTERNAL_MODE_BACK)
	_generated_layers.append(canvas_layer)

	for index in effects.size():
		var effect := effects[index]

		if not _validate_effect(effect, layer_name, index, registered_effects):
			continue

		registered_effects[effect.get_instance_id()] = true
		_create_effect_nodes(canvas_layer, effect, index)


func _validate_effect(
	effect: PostProcessEffect,
	layer_name: StringName,
	index: int,
	registered_effects: Dictionary[int, bool],
) -> bool:
	if effect == null:
		push_warning("PostProcessing ignored a null effect at %s[%d]." % [layer_name, index])
		return false

	var instance_id := effect.get_instance_id()

	if registered_effects.has(instance_id):
		push_warning("PostProcessing ignored a duplicate Resource at %s[%d]." % [layer_name, index])
		return false

	if effect.get_shader() == null:
		push_warning(
			"PostProcessing ignored an effect without a Shader at %s[%d]."
			% [layer_name, index]
		)
		return false

	return true


func _create_effect_nodes(
	canvas_layer: CanvasLayer,
	effect: PostProcessEffect,
	index: int,
) -> void:
	var back_buffer_copy := BackBufferCopy.new()
	back_buffer_copy.name = "BackBufferCopy%d" % index
	back_buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	canvas_layer.add_child(back_buffer_copy, false, Node.INTERNAL_MODE_BACK)

	var material := ShaderMaterial.new()
	material.shader = effect.get_shader()

	var rect := ColorRect.new()
	rect.name = "Effect%d" % index
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = material
	canvas_layer.add_child(rect, false, Node.INTERNAL_MODE_BACK)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var binding := EffectBinding.new()
	binding.effect = effect
	binding.back_buffer_copy = back_buffer_copy
	binding.rect = rect
	binding.material = material
	binding.changed_callback = _on_effect_changed.bind(binding)
	_effect_bindings.append(binding)

	_set_binding_enabled(binding, effect.enabled)
	effect.apply_to(material)
	effect.changed.connect(binding.changed_callback, CONNECT_DEFERRED)


func _set_binding_enabled(binding: EffectBinding, is_enabled: bool) -> void:
	binding.back_buffer_copy.visible = is_enabled
	binding.rect.visible = is_enabled


func _disconnect_effects() -> void:
	for binding in _effect_bindings:
		if (
			is_instance_valid(binding.effect)
			and binding.effect.changed.is_connected(binding.changed_callback)
		):
			binding.effect.changed.disconnect(binding.changed_callback)

		binding.changed_callback = Callable()

	_effect_bindings.clear()


func _clear_generated_layers(is_immediate: bool = false) -> void:
	for canvas_layer in _generated_layers:
		if not is_instance_valid(canvas_layer):
			continue

		if canvas_layer.get_parent() == self:
			remove_child(canvas_layer)

		if is_immediate:
			canvas_layer.free()
		else:
			canvas_layer.queue_free()

	_generated_layers.clear()


func _apply_enabled_state() -> void:
	for canvas_layer in _generated_layers:
		if is_instance_valid(canvas_layer):
			canvas_layer.visible = enabled


class EffectBinding:
	var effect: PostProcessEffect
	var back_buffer_copy: BackBufferCopy
	var rect: ColorRect
	var material: ShaderMaterial
	var changed_callback: Callable
