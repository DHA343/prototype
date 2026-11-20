@tool
class_name PassSourceContext
extends RefCounted
## A pass source lives until PostProcessing rebuilds or leaves the tree.
## Preceding passes are ordered and restricted to the source's CanvasLayer.

var main_viewport: Viewport
var layer_index: int
var preceding_passes: Array[Pass]

var _enabled_check: Callable


func _init(
	viewport: Viewport,
	layer: int,
	passes: Array[Pass],
	enabled_check: Callable,
) -> void:
	main_viewport = viewport
	layer_index = layer
	preceding_passes = passes
	preceding_passes.make_read_only()
	_enabled_check = enabled_check


func is_enabled() -> bool:
	return _enabled_check.is_valid() and _enabled_check.call()


class Pass:
	extends RefCounted
	## The material is shared so parameter changes also reach the source's replay.
	var material: ShaderMaterial

	var _enabled_check: Callable


	func _init(pass_material: ShaderMaterial, enabled_check: Callable) -> void:
		material = pass_material
		_enabled_check = enabled_check


	func is_enabled() -> bool:
		return _enabled_check.is_valid() and _enabled_check.call()
