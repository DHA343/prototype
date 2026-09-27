extends SceneTree

var _failures: int = 0
var _sound_count: int = 0
var _shake_count: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var world := Node2D.new()
	root.add_child(world)
	var feedback := Feedback.new()
	feedback.sound_requested.connect(func(_request: SoundRequest) -> void: _sound_count += 1)
	feedback.camera_shake_requested.connect(func(_request: CameraShakeRequest) -> void: _shake_count += 1)
	var player := load("res://player/player.tscn").instantiate() as Player
	world.add_child(player)
	player.setup(feedback)
	player.set_physics_process(false)
	player.global_position = Vector2(0.0, 32.0)
	player.reset_position_interpolation()
	_check(player.visual.global_position == Vector2.ZERO, "Player visual must use the foot offset.")
	_check(player.sweep_hit.global_position == Vector2.ZERO, "Player sweep must match its visual.")
	_check(player.get_equipped_charge_ability().id == &"homing_missiles", "Initial ability must be missiles.")

	player.movement.update(0.1, Vector2.ZERO, Vector2.RIGHT * 100.0)
	_check(is_equal_approx(player.movement.velocity.x, 1000.0), "Mouse pursuit must accelerate.")
	var brake_press := InputEventMouseButton.new()
	brake_press.button_index = MOUSE_BUTTON_RIGHT
	brake_press.pressed = true
	root.push_input(brake_press)
	await process_frame
	_check(player.brake.is_active, "Brake action must reach the player's input handler.")
	player.charge.update(0.5)
	player.brake.update(0.1)
	_check(player.movement.velocity.length() < 1000.0, "Brake must decelerate.")
	_check(is_equal_approx(player.charge_level, 0.5), "Brake must charge.")
	player.set_brake_pressed(false)
	_check(_count_missiles(world) == 14, "Half charge must emit 14 missiles.")
	_clear_attacks(world)
	await process_frame

	player.set_brake_pressed(true)
	player.charge.update(1.0)
	player.hitstop.request()
	_check(player.request_boost(), "First boost must activate.")
	_check(not player.hitstop.is_stopped, "Boost must cancel hitstop.")
	_check(not player.brake.is_active, "Boost must interrupt brake.")
	_check(_count_missiles(world) == 26, "Boost interruption must release the charged attack.")
	_check(not player.request_boost(), "Boost cooldown must reject repeated activation.")
	player.set_brake_pressed(true)
	_check(not player.brake.is_active, "Interrupted brake must wait for release.")
	player.set_brake_pressed(false)
	_clear_attacks(world)
	await process_frame

	var area := SpawnArea.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(1920.0, 1080.0)
	var area_shape := CollisionShape2D.new()
	area_shape.name = "CollisionShape2D"
	area_shape.shape = rectangle
	area.add_child(area_shape)
	world.add_child(area)
	var enemy := load("res://enemy/enemy.tscn").instantiate() as Enemy
	world.add_child(enemy)
	enemy.global_position = Vector2(100.0, 40.0)
	enemy.start(area)
	enemy.set_physics_process(false)
	_check(enemy.health.current_health == 100.0, "Enemy HP must match test.")
	_check(enemy.hurtbox.global_position == Vector2(100.0, 0.0), "Enemy hurtbox must use the foot offset.")
	_check(enemy.get_node("Hurtbox/CollisionShape2D").shape.radius == 40.0, "Enemy hit radius must be 40.")
	_check(enemy.movement.target == null, "Enemy must wander without a target.")
	enemy.movement.update(1.0, Vector2.ZERO)
	_check(enemy.movement.velocity.length() > 0.0, "An untargeted enemy must wander.")
	enemy.movement.clear()
	enemy.movement.update(1.0, Vector2(1100.0, 0.0))
	_check(enemy.movement.velocity.x < 0.0, "Wandering outside the boundary must steer inward.")
	await create_timer(0.06).timeout
	_check(enemy.get_node("Hurtbox/CollisionShape2D").disabled, "Growing enemy must not receive collisions.")
	await enemy.spawn_animation.grow_finished
	await physics_frame
	await process_frame
	_check(not enemy.get_node("Hurtbox/CollisionShape2D").disabled, "Enemy must become hittable after growth.")

	player.movement.clear()
	player.movement.add_velocity(Vector2(7000.0, 0.0))
	player.sweep_hit.detect(Vector2(200.0, 0.0))
	_check(is_equal_approx(enemy.health.current_health, 55.0), "Swept body hit must deal speed-based damage.")
	_check(is_equal_approx(enemy.knockback.velocity.length(), 1500.0), "Body impulse must not be capped at 1200.")
	_check(player.hitstop.is_stopped, "Body hit must request hitstop.")
	_check(_shake_count == 1, "Body hit must reach prototype camera feedback.")
	player.sweep_hit.detect(Vector2(200.0, 0.0))
	_check(is_equal_approx(enemy.health.current_health, 55.0), "Continuous contact must not hit twice.")
	_check(enemy.spawn_animation._phase == EnemySpawnAnimation.Phase.COMPLETE, "Hit must cancel spawn animation.")
	_check(enemy.spawn_animation._grow_tween == null, "Cancelled spawn tween must release its scale writer.")
	await create_timer(1.5).timeout
	_check(enemy.get_node("VisualRoot").scale.is_equal_approx(Vector2.ONE), "Hit scale must settle without spawn interference.")
	_check(enemy.get_node("Hurtbox/CollisionShape2D").shape.radius == 40.0, "Visual scale must not resize damage detection.")

	var missiles := player.get_equipped_charge_ability() as HomingMissileDefinition
	var missile := missiles.missile_scene.instantiate() as HomingMissile
	missile.configure(Vector2.RIGHT, missiles)
	missile.position = Vector2(30.0, 0.0)
	world.add_child(missile)
	await create_timer(0.2).timeout
	_check(enemy.health.current_health < 55.0, "Missile collision must reach prototype damage handling.")
	_clear_attacks(world)
	await process_frame

	var shockwave := load("res://player/charge/abilities/shockwave/shockwave_charge_ability_definition.tres") as ChargeAbilityDefinition
	_check(player.equip_charge_ability(shockwave), "Shockwave must equip through the charge slot.")
	player.set_brake_pressed(true)
	player.charge.update(1.0)
	player.set_brake_pressed(false)
	var waves: Array[Node] = world.get_children().filter(func(node: Node) -> bool: return node is Shockwave)
	_check(waves.size() == 1, "Full charge must spawn one shockwave.")
	_check((waves[0] as Node2D).global_position == player.sweep_hit.global_position, "Attack origin must match ball center.")
	await create_timer(0.35).timeout
	_check(not is_instance_valid(enemy), "Shockwave must damage and kill its target.")
	_check(_sound_count > 0, "Attack sound requests must reach prototype feedback.")
	world.queue_free()
	await process_frame

	var main := load("res://main/main.tscn").instantiate() as Main
	root.add_child(main)
	main.player.set_physics_process(false)
	_check(main.enemies.get_child_count() == 30, "Prototype population must stay at 30.")
	_check(not main.crowd_manager._members.has(main.player), "Ball must not participate in crowd pushing.")
	var spawned_enemy := main.enemies.get_child(0) as Enemy
	var lethal_hit := HitData.new()
	lethal_hit.damage = 100.0
	lethal_hit.hit_position = spawned_enemy.hurtbox.global_position
	spawned_enemy.hurtbox.receive_hit(lethal_hit)
	await process_frame
	_check(main.enemies.get_child_count() == 29, "Lethal damage must remove the enemy.")
	await create_timer(0.6).timeout
	_check(main.enemies.get_child_count() == 30, "Prototype respawn must replenish the enemy.")
	_check(main.crowd_manager._members.size() == 30, "Crowd registration must follow death and respawn.")
	main.queue_free()
	# Allow the audio server to release active voices before terminating the test process.
	await create_timer(0.1).timeout
	print("Ball port checks: %s" % ("PASS" if _failures == 0 else "FAIL (%d)" % _failures))
	quit(0 if _failures == 0 else 1)


func _count_missiles(world: Node) -> int:
	var count := 0
	for child: Node in world.get_children():
		if child is HomingMissile and not child.is_queued_for_deletion():
			count += 1
	return count


func _clear_attacks(world: Node) -> void:
	for child: Node in world.get_children():
		if child is HomingMissile or child is Shockwave:
			child.queue_free()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(message)
