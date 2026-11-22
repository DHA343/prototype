extends PinballFlippers

var controllers: Dictionary = {}


static func install(main: Node) -> void:
	var node := main.get_node("Playfield/Flippers")
	assert(not node.is_inside_tree())
	var values := {}
	for property: Dictionary in node.get_script().get_script_property_list():
		if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_STORAGE:
			values[property.name] = node.get(property.name)
	node.set_script(load("res://experiments/flippers/release_flippers.gd"))
	for key: String in values:
		node.set(key, values[key])


func attach(target: CharacterBody2D, controller: RefCounted) -> void:
	var id := target.get_instance_id()
	controllers[id] = controller
	var cleanup := _forget.bind(id)
	if not target.tree_exiting.is_connected(cleanup):
		target.tree_exiting.connect(cleanup, CONNECT_ONE_SHOT)


func refresh_target(target: CharacterBody2D, next_velocity_y: float) -> void:
	var controller: RefCounted = controllers.get(target.get_instance_id())
	if controller != null:
		controller.refresh(next_velocity_y)
	else:
		super.refresh_target(target, next_velocity_y)


func _forget(id: int) -> void:
	controllers.erase(id)
