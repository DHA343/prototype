extends Node2D

const CANVAS_SIZE: Vector2 = Vector2(1920.0, 1080.0)
const CHECKER_SIZE: float = 48.0
const PALETTE = [
	Color(0.13, 0.19, 0.27),
	Color(0.48, 0.55, 0.67),
	Color(0.95, 0.08, 0.08),
	Color(0.08, 0.95, 0.16),
	Color(0.08, 0.2, 0.98),
	Color(0.08, 0.9, 0.92),
	Color(0.96, 0.09, 0.88),
	Color(0.98, 0.88, 0.12),
	Color(0.92, 0.94, 0.98),
	Color(1.2, 0.38, 0.18),
	Color(0.25, 1.5, 0.72),
	Color(0.5, 0.35, 2.0),
	Color(3.0, 2.5, 1.8),
]
const RADII: Array[float] = [22.0, 32.0, 44.0]

var _feedback: Feedback = Feedback.new()
var _spawn_index: int = 0
var _motion_time: float = 0.0

@onready var _orb: Orb = $Actors/Orb
@onready var _enemies: Node2D = $Actors/Enemies
@onready var _crowd_manager: CrowdManager = $CrowdManager
@onready var _spawn_area: SpawnArea = $SpawnArea
@onready var _enemy_spawner: EnemySpawner = $EnemySpawner
@onready var _sweep_target_a: Node2D = $SweepTargetA
@onready var _sweep_target_b: Node2D = $SweepTargetB
@onready var _sound_output: WorldSoundOutput = $WorldSoundOutput
@onready var _world_ui_layer: CanvasLayer = $WorldUILayer
@onready var _damage_spawner: DamageNumberSpawner = $WorldUILayer/DamageNumberSpawner


func _ready() -> void:
	_fit_canvas()
	get_viewport().size_changed.connect(_fit_canvas)
	_feedback.sound_requested.connect(_sound_output.request)
	_orb.setup(_feedback)
	_enemy_spawner.enemy_spawned.connect(_on_enemy_spawned)
	_enemy_spawner.setup(_enemies, _spawn_area)
	_enemy_spawner.start()


func _process(delta: float) -> void:
	_motion_time += delta
	_sweep_target_a.position = Vector2(
		960.0 + 760.0 * sin(_motion_time * 0.26),
		360.0 + 220.0 * sin(_motion_time * 0.39)
	)
	_sweep_target_b.position = Vector2(
		960.0 - 760.0 * sin(_motion_time * 0.21),
		720.0 + 180.0 * cos(_motion_time * 0.33)
	)


func _draw() -> void:
	draw_rect(Rect2(0.0, 0.0, 640.0, CANVAS_SIZE.y), Color(0.11, 0.13, 0.17))
	for row in int(CANVAS_SIZE.y / CHECKER_SIZE) + 1:
		for column in int(640.0 / CHECKER_SIZE) + 1:
			var cell_color := Color(0.18, 0.21, 0.27)
			if (row + column) % 2 != 0:
				cell_color = Color(0.27, 0.3, 0.37)
			draw_rect(Rect2(
				640.0 + float(column) * CHECKER_SIZE,
				float(row) * CHECKER_SIZE,
				CHECKER_SIZE,
				CHECKER_SIZE
			), cell_color)
	for column in 128:
		var blend := float(column) / 127.0
		var gradient_color := Color(0.07, 0.13, 0.32).lerp(Color(0.78, 0.52, 0.34), blend)
		draw_rect(Rect2(1280.0 + float(column) * 5.0, 0.0, 5.0, CANVAS_SIZE.y), gradient_color)


func _on_enemy_spawned(enemy: Enemy) -> void:
	var variation := _spawn_index
	_spawn_index += 1
	var radius: float = RADII[variation % RADII.size()]
	var body_color: Color = PALETTE[variation % PALETTE.size()]
	var visual_root := enemy.get_node("VisualRoot") as Node2D
	var production_visual := enemy.get_node("VisualRoot/Visual") as CanvasItem
	production_visual.hide()
	visual_root.position.y = -radius
	var test_visual := CRTTestEnemyVisual.new()
	visual_root.add_child(test_visual)
	test_visual.configure(variation % 5, radius, body_color)

	enemy.hurtbox.position.y = -radius
	var collision := enemy.get_node("Hurtbox/CollisionShape2D") as CollisionShape2D
	var circle := collision.shape.duplicate() as CircleShape2D
	circle.radius = radius
	collision.shape = circle
	var shadow := enemy.get_node("DropShadow") as DropShadow
	shadow.size = Vector2(radius * 1.5, radius * 0.6)

	enemy.movement.wander_speed = 70.0 + float(variation % 5) * 24.0
	enemy.movement.chase_speed = 100.0 + float(variation % 4) * 32.0
	match variation % 4:
		0:
			enemy.movement.target = _orb
		1:
			enemy.movement.target = _sweep_target_a
		2:
			enemy.movement.target = _sweep_target_b
		_:
			enemy.movement.max_turn_rate = 3.0

	_crowd_manager.register_member(enemy, enemy.crowd)
	enemy.damaged.connect(_on_enemy_damaged)
	enemy.sound_requested.connect(_feedback.sound_requested.emit)


func _on_enemy_damaged(
	requested_damage: float,
	hit_position: Vector2,
	resulting_knockback_velocity: Vector2
) -> void:
	var layer_inverse := _world_ui_layer.transform.affine_inverse()
	_damage_spawner.spawn(
		requested_damage,
		layer_inverse.basis_xform(resulting_knockback_velocity),
		layer_inverse * hit_position
	)


func _fit_canvas() -> void:
	var canvas_scale := get_viewport_rect().size / CANVAS_SIZE
	scale = canvas_scale
	$WorldUILayer.transform = Transform2D.IDENTITY.scaled(canvas_scale)
