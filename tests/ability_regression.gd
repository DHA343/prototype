extends SceneTree
## Run: godot --headless --path . --script tests/ability_regression.gd

const PUNCH_ABILITY_SCENE: PackedScene = preload("res://player/ability/punch/punch_ability.tscn")

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_check_punch_timing()
	_check_press_buffer()
	_check_ability_replacement()
	_check_feedback_relay()
	await process_frame
	print("Ability regression: %d failure(s)." % _failures)
	quit(1 if _failures > 0 else 0)


func _check_punch_timing() -> void:
	var fixture := _create_fixture()
	var slot: AbilitySlot = fixture.slot
	var attack_root: Node2D = fixture.attack_root

	slot.update_input(0.0, true, true, false, Vector2.RIGHT)
	_expect(attack_root.get_child_count() == 1, "Press activates Punch immediately.")
	slot.update_input(0.05, false, false, true, Vector2.RIGHT)
	slot.update_input(0.0, true, true, false, Vector2.RIGHT)
	_expect(attack_root.get_child_count() == 1, "Release does not reset Punch cooldown.")
	slot.update_input(0.16, false, true, false, Vector2.RIGHT)
	_expect(attack_root.get_child_count() == 2, "Held input repeats after the attack interval.")
	slot.update_input(0.01, true, true, false, Vector2.RIGHT)
	_expect(attack_root.get_child_count() == 2, "Repeated presses cannot bypass the attack interval.")
	_fixture_free(fixture)


func _check_press_buffer() -> void:
	var buffered_fixture := _create_fixture()
	var buffered_slot: AbilitySlot = buffered_fixture.slot
	var buffered_root: Node2D = buffered_fixture.attack_root
	buffered_slot.update_input(0.0, true, false, false, Vector2.RIGHT)
	buffered_slot.update_input(0.15, true, false, false, Vector2.RIGHT)
	_expect(buffered_root.get_child_count() == 1, "Buffered press does not activate during cooldown.")
	buffered_slot.update_input(0.051, false, false, false, Vector2.RIGHT)
	_expect(buffered_root.get_child_count() == 2, "Buffered tap activates when cooldown ends.")
	_fixture_free(buffered_fixture)

	var expired_fixture := _create_fixture()
	var expired_slot: AbilitySlot = expired_fixture.slot
	var expired_root: Node2D = expired_fixture.attack_root
	expired_slot.update_input(0.0, true, false, false, Vector2.RIGHT)
	expired_slot.update_input(0.05, false, false, true, Vector2.RIGHT)
	expired_slot.update_input(0.05, true, false, false, Vector2.RIGHT)
	expired_slot.update_input(0.09, false, false, false, Vector2.RIGHT)
	expired_slot.update_input(0.01, false, false, false, Vector2.RIGHT)
	_expect(expired_root.get_child_count() == 1, "Expired buffered press does not activate.")
	_fixture_free(expired_fixture)

	var refreshed_fixture := _create_fixture()
	var refreshed_slot: AbilitySlot = refreshed_fixture.slot
	var refreshed_root: Node2D = refreshed_fixture.attack_root
	refreshed_slot.update_input(0.0, true, false, false, Vector2.RIGHT)
	refreshed_slot.update_input(0.12, true, false, false, Vector2.RIGHT)
	refreshed_slot.update_input(0.04, true, false, false, Vector2.RIGHT)
	refreshed_slot.update_input(0.041, false, false, true, Vector2.RIGHT)
	_expect(refreshed_root.get_child_count() == 2, "Latest buffered press is consumed once.")
	_fixture_free(refreshed_fixture)


func _check_ability_replacement() -> void:
	var fixture := _create_fixture()
	var slot: AbilitySlot = fixture.slot
	var old_ability := slot.get_ability()
	slot.update_input(0.0, true, false, false, Vector2.RIGHT)
	_expect(slot.set_ability(PUNCH_ABILITY_SCENE), "Ability slot accepts a valid Ability scene.")
	_expect(slot.get_ability() != old_ability, "Ability replacement creates a new instance.")
	slot.update_input(0.0, true, false, false, Vector2.RIGHT)
	_expect(fixture.attack_root.get_child_count() == 2, "Replacement Ability is setup and receives input.")
	slot.clear_ability()
	slot.update_input(1.0, true, true, true, Vector2.RIGHT)
	_expect(fixture.attack_root.get_child_count() == 2, "Cleared ability slot ignores input.")
	_fixture_free(fixture)


func _check_feedback_relay() -> void:
	var fixture_root := Node2D.new()
	var attack_root := Node2D.new()
	var player_input := PlayerInput.new()
	var controller := AbilityController.new()
	var slot := AbilitySlot.new()
	var sound_count := [0]
	var trauma := [0.0]
	slot.slot_id = &"primary"
	slot.input_action = &"ability_primary"
	slot.initial_ability_scene = PUNCH_ABILITY_SCENE
	root.add_child(fixture_root)
	fixture_root.add_child(attack_root)
	fixture_root.add_child(player_input)
	fixture_root.add_child(controller)
	controller.add_child(slot)
	controller.sound_requested.connect(func(_request: SoundRequest): sound_count[0] += 1)
	controller.camera_shake_requested.connect(func(value: float): trauma[0] = value)
	controller.setup(fixture_root, player_input, attack_root)
	var ability := controller.get_ability(&"primary")
	ability.sound_requested.emit(SoundRequest.new(SoundCue.new(), Vector2.ZERO, ability))
	ability.camera_shake_requested.emit(0.25)
	_expect(sound_count[0] == 1 and is_equal_approx(trauma[0], 0.25), "Ability feedback relays through the controller.")
	fixture_root.queue_free()


func _create_fixture() -> Dictionary[StringName, Node]:
	var fixture_root := Node2D.new()
	var attack_root := Node2D.new()
	var slot := AbilitySlot.new()
	slot.initial_ability_scene = PUNCH_ABILITY_SCENE
	root.add_child(fixture_root)
	fixture_root.add_child(attack_root)
	fixture_root.add_child(slot)
	slot.setup(fixture_root, attack_root)
	var ability := slot.get_ability() as PunchAbility
	ability.attack_interval = 0.20
	ability.press_buffer_duration = 0.08
	return {&"root": fixture_root, &"slot": slot, &"attack_root": attack_root}


func _fixture_free(fixture: Dictionary[StringName, Node]) -> void:
	var fixture_root := fixture[&"root"]
	fixture_root.queue_free()


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
