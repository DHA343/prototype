class_name PostProcessPreset
extends Resource

## Processes the whole screen drawn through Layer 1, including preceding layers.
@export var layer_1_effects: Array[PostProcessEffect] = []
## Processes the whole screen drawn through Layer 2, including Layer 1 and its effects.
@export var layer_2_effects: Array[PostProcessEffect] = []
