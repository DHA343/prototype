class_name CrowdManager
extends Node

@export_range(0.0, 96.0, 3.0, "suffix:px") var avoidance_gap: float = 24.0
@export_range(0.0, 600.0, 15.0, "suffix:px/s") var separation_speed: float = 105.0
@export_range(0.0, 1.0, 0.05) var stiffness: float = 0.8
@export_range(0.0, 1800.0, 30.0, "suffix:px/s") var max_correction_speed: float = 450.0

var _grid: Dictionary[Vector2i, Array] = {}


## Requests displacement only. Enemy resolves every request against world collision.
func calculate(enemies: Array[Enemy], delta: float, goal: Vector2) -> void:
	_grid.clear()
	var largest_radius := 1.0
	for enemy: Enemy in enemies:
		enemy.crowd_motion = Vector2.ZERO
		largest_radius = maxf(largest_radius, enemy.radius)
	var cell_size := largest_radius * 2.0 + avoidance_gap
	for index in enemies.size():
		var cell := _cell(enemies[index].global_position, cell_size)
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(index)
	for index in enemies.size():
		var cell := _cell(enemies[index].global_position, cell_size)
		for x in range(cell.x - 1, cell.x + 2):
			for y in range(cell.y - 1, cell.y + 2):
				for other: int in _grid.get(Vector2i(x, y), []):
					if other > index:
						_separate(enemies[index], enemies[other], index, other, delta, goal)
	for enemy: Enemy in enemies:
		enemy.crowd_motion = enemy.crowd_motion.limit_length(max_correction_speed * delta)


func _separate(
	a: Enemy, b: Enemy, index_a: int, index_b: int, delta: float, goal: Vector2,
) -> void:
	var offset := b.global_position - a.global_position
	var distance := offset.length()
	var minimum := a.radius + b.radius
	var avoid := minimum + avoidance_gap
	if distance >= avoid:
		return
	var normal := offset / distance if distance > 0.0001 else Vector2.RIGHT.rotated(
		deg_to_rad(float((index_a * 73 + index_b * 151) % 360)))
	var proximity := clampf((avoid - distance) / maxf(avoidance_gap, 0.001), 0.0, 1.0)
	var correction := separation_speed * proximity * proximity * delta
	correction += maxf(0.0, minimum - distance) * stiffness
	var weight_a := 0.5
	if a.move_speed > 0.0 and b.move_speed > 0.0:
		# Right of way breaks symmetric jams at a one-enemy-wide exit.
		var distance_a := a.global_position.distance_squared_to(goal)
		var distance_b := b.global_position.distance_squared_to(goal)
		var a_first := distance_a < distance_b or (is_equal_approx(distance_a, distance_b)
			and a.get_instance_id() < b.get_instance_id())
		weight_a = 0.0 if a_first else 1.0
	var motion := normal * correction
	a.crowd_motion -= motion * weight_a
	b.crowd_motion += motion * (1.0 - weight_a)


func _cell(point: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(floori(point.x / cell_size), floori(point.y / cell_size))
