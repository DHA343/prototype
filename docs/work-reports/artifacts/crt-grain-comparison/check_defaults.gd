extends SceneTree


func _initialize() -> void:
	var script := GDScript.new()
	script.source_code = "@tool\nextends Resource\n@export var previous: float = 0.7\n"
	var initial_error := script.reload()
	var resource: Resource = script.new()
	resource.set("previous", 0.18)
	script.source_code += "@export var added: float = 1.5\n@export var switched: bool = true\n"
	var reload_error := script.reload(true)
	var fresh: Resource = script.new()
	var effect := CRTDisplayExperimental.new()
	var effect_defaults := {
		"enabled": effect.grain_enabled,
		"pattern": effect.grain_pattern,
		"strength": effect.grain_strength,
		"size": effect.grain_size,
	}
	var scene := load("res://presentation/post_processing/test_scenes/crt_display_test/crt_display_test.tscn") as PackedScene
	var scene_state := scene.get_state()
	var saved_effect: Resource
	for node_index in scene_state.get_node_count():
		for property_index in scene_state.get_node_property_count(node_index):
			if scene_state.get_node_property_name(node_index, property_index) == &"composite_effects":
				var effects: Array = scene_state.get_node_property_value(node_index, property_index)
				saved_effect = effects[2]
	var roundtrips: Array[Dictionary] = []
	var temporary_path := "res://docs/work-reports/artifacts/crt-grain-comparison/roundtrip.tres"
	for pattern in 3:
		effect.grain_pattern = pattern
		effect.grain_strength = 0.18
		var save_error := ResourceSaver.save(effect, temporary_path)
		var restored := ResourceLoader.load(temporary_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		roundtrips.append({
			"pattern": restored.get("grain_pattern"),
			"enabled": restored.get("grain_enabled"),
			"strength": restored.get("grain_strength"),
			"size": restored.get("grain_size"),
			"save_error": save_error,
		})
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var result := {
		"initial_error": initial_error,
		"reload_error": reload_error,
		"existing": {"previous": resource.get("previous"), "added": resource.get("added"), "switched": resource.get("switched")},
		"fresh": {"added": fresh.get("added"), "switched": fresh.get("switched")},
		"effect_new": effect_defaults,
		"effect_saved": {
			"enabled": saved_effect.get("grain_enabled"),
			"pattern": saved_effect.get("grain_pattern"),
			"strength": saved_effect.get("grain_strength"),
			"size": saved_effect.get("grain_size"),
		},
		"roundtrips": roundtrips,
	}
	print(JSON.stringify(result))
	var file := FileAccess.open("res://docs/work-reports/artifacts/crt-grain-comparison/defaults.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	quit()
