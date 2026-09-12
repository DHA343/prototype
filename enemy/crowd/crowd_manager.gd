class_name CrowdManager
extends Node

@export_group("Grid")
@export_range(1.0, 512.0, 1.0, "suffix:unit") var cell_size: float = 80.0:
	set(value):
		cell_size = maxf(value, 0.01)

@export_group("Solver")
@export_range(1, 8, 1) var solver_iterations: int = 2:
	set(value):
		solver_iterations = maxi(value, 1)

@export_range(0.0, 1.0, 0.05) var stiffness: float = 0.8:
	set(value):
		stiffness = clampf(value, 0.0, 1.0)

@export_range(0.0, 1000.0, 10.0, "suffix:unit/s") var max_correction_speed: float = 300.0:
	set(value):
		max_correction_speed = maxf(value, 0.0)

var _members: Array[Node2D] = []
var _radii: Array[float] = []
var _positions: Array[Vector2] = []
var _corrections: Array[Vector2] = []
var _grid: Dictionary = {}
var _pairs: Array[Vector2i] = []


func _ready() -> void:
	process_physics_priority = 100


func _physics_process(delta: float) -> void:
	_remove_invalid_members()
	if _members.size() < 2:
		return

	_copy_positions()
	_build_grid()
	_build_pairs()
	_solve(delta)
	_write_positions()


func register_member(member: Node2D, radius: float) -> void:
	if not is_instance_valid(member):
		return

	var member_index := _members.find(member)
	if member_index >= 0:
		_radii[member_index] = maxf(radius, 0.0)
		return

	_members.append(member)
	_radii.append(maxf(radius, 0.0))


func unregister_member(member: Node2D) -> void:
	var member_index := _members.find(member)
	if member_index < 0:
		return

	_members.remove_at(member_index)
	_radii.remove_at(member_index)


func _copy_positions() -> void:
	_positions.resize(_members.size())
	_corrections.resize(_members.size())

	for member_index in _members.size():
		_positions[member_index] = _members[member_index].global_position


func _build_grid() -> void:
	_grid.clear()

	for member_index in _members.size():
		var radius := _radii[member_index]
		var radius_offset := Vector2(radius, radius)
		var minimum_cell := _world_to_cell(_positions[member_index] - radius_offset)
		var maximum_cell := _world_to_cell(_positions[member_index] + radius_offset)

		for cell_x in range(minimum_cell.x, maximum_cell.x + 1):
			for cell_y in range(minimum_cell.y, maximum_cell.y + 1):
				var cell := Vector2i(cell_x, cell_y)
				var cell_indices: Array
				if _grid.has(cell):
					cell_indices = _grid[cell]
				else:
					cell_indices = []
					_grid[cell] = cell_indices
				cell_indices.append(member_index)


func _build_pairs() -> void:
	_pairs.clear()
	var pair_keys: Dictionary = {}

	for cell_indices: Array in _grid.values():
		for first_index in range(cell_indices.size() - 1):
			var member_a_index: int = cell_indices[first_index]
			for second_index in range(first_index + 1, cell_indices.size()):
				var member_b_index: int = cell_indices[second_index]
				var pair := Vector2i(
					mini(member_a_index, member_b_index),
					maxi(member_a_index, member_b_index)
				)
				if pair_keys.has(pair):
					continue

				pair_keys[pair] = true
				_pairs.append(pair)


func _solve(delta: float) -> void:
	var iteration_count := solver_iterations
	var max_iteration_correction := max_correction_speed * maxf(delta, 0.0)
	max_iteration_correction /= float(iteration_count)

	for _iteration in iteration_count:
		_accumulate_corrections()
		_apply_corrections(max_iteration_correction)


func _accumulate_corrections() -> void:
	for member_index in _members.size():
		_corrections[member_index] = Vector2.ZERO

	for pair in _pairs:
		var member_a_index := pair.x
		var member_b_index := pair.y
		var delta := _positions[member_b_index] - _positions[member_a_index]
		var distance := delta.length()
		var minimum_distance := _radii[member_a_index] + _radii[member_b_index]
		if distance >= minimum_distance:
			continue

		var normal := _fallback_normal(member_a_index, member_b_index)
		if not is_zero_approx(distance):
			normal = delta / distance

		var overlap := minimum_distance - distance
		var half_correction := normal * overlap * stiffness * 0.5
		_corrections[member_a_index] -= half_correction
		_corrections[member_b_index] += half_correction


func _apply_corrections(max_iteration_correction: float) -> void:
	for member_index in _members.size():
		var correction := _corrections[member_index].limit_length(max_iteration_correction)
		_positions[member_index] += correction


func _write_positions() -> void:
	for member_index in _members.size():
		var member := _members[member_index]
		if is_instance_valid(member):
			member.global_position = _positions[member_index]


func _remove_invalid_members() -> void:
	for member_index in range(_members.size() - 1, -1, -1):
		if is_instance_valid(_members[member_index]):
			continue

		_members.remove_at(member_index)
		_radii.remove_at(member_index)


func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(world_position.x / cell_size),
		floori(world_position.y / cell_size)
	)


func _fallback_normal(member_a_index: int, member_b_index: int) -> Vector2:
	var angle_degrees := float((member_a_index * 73 + member_b_index * 151) % 360)
	return Vector2.from_angle(deg_to_rad(angle_degrees))
