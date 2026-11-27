@tool
extends Resource

## Shared palette. The first color is also used by the flat variant.
@export var color_gradient: Gradient = Gradient.new():
	set(value):
		color_gradient = value
		emit_changed()
## How long each part of the trail remains visible.
@export_range(0.04, 0.40, 0.01, "suffix:s") var lifetime: float = 0.16:
	set(value):
		lifetime = value
		emit_changed()
## Time each circle keeps its initial radius.
@export_range(0.0, 0.40, 0.01, "suffix:s") var width_hold: float = 0.04:
	set(value):
		width_hold = value
		emit_changed()
## Root width relative to the ball diameter.
@export_range(0.50, 1.50, 0.05, "suffix:×") var width_scale: float = 0.95:
	set(value):
		width_scale = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var opacity: float = 0.88:
	set(value):
		opacity = value
		emit_changed()
## Fraction of the lifetime that keeps the first palette color.
@export_range(0.0, 0.80, 0.01) var root_color_hold: float = 0.28:
	set(value):
		root_color_hold = value
		emit_changed()
## How far the outer edge shifts toward the last palette color.
@export_range(0.0, 1.0, 0.01) var edge_color_strength: float = 1.0:
	set(value):
		edge_color_strength = value
		emit_changed()
