extends Node2D

@export var spawner: EnemySpawner


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode != KEY_E and key.keycode != KEY_E:
		return

	var enemy := spawner.enemy_scene.instantiate() as Enemy
	assert(enemy != null, "Enemy scene must have an Enemy root.")
	enemy.position = spawner.spawn_parent.to_local(get_global_mouse_position())
	spawner.spawn_parent.add_child(enemy)
	spawner.enemy_spawned.emit(enemy)
	get_viewport().set_input_as_handled()
