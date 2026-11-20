class_name EnemyRoutes
extends Node

## One navigation map per body radius. Flippers stay dynamic physics obstacles.
var revision: int = 0
var _boundary: PinballBoundary
var _bumpers: Array[PinballBumper] = []
var _maps: Dictionary[float, RID] = {}
var _regions: Dictionary[float, RID] = {}
var _fingerprint: Array = []


func _exit_tree() -> void:
	_clear_maps()


func setup(boundary: PinballBoundary, bumpers: Array[PinballBumper]) -> void:
	_boundary = boundary
	_bumpers = bumpers
	_boundary.geometry_changed.connect(_invalidate)
	refresh()


func refresh() -> void:
	var current: Array = [_boundary.global_transform]
	for bumper: PinballBumper in _bumpers:
		current.append(bumper.global_transform)
		current.append(bumper.radius)
	if current != _fingerprint:
		_fingerprint = current
		_invalidate()


func prepare(radius: float) -> void:
	if _maps.has(radius):
		return
	var navigation := NavigationPolygon.new()
	navigation.cell_size = 3.0
	navigation.agent_radius = radius + 1.5
	var geometry := NavigationMeshSourceGeometryData2D.new()
	var outline := _boundary.traversable_outline()
	if outline.size() >= 3:
		geometry.add_traversable_outline(outline)
	for bumper: PinballBumper in _bumpers:
		var points := PackedVector2Array()
		for index in 48:
			points.append(bumper.to_global(Vector2.RIGHT.rotated(TAU * index / 48.0) * bumper.radius))
		geometry.add_obstruction_outline(points)
	NavigationServer2D.bake_from_source_geometry_data(navigation, geometry)
	var map := NavigationServer2D.map_create()
	NavigationServer2D.map_set_cell_size(map, 3.0)
	NavigationServer2D.map_set_active(map, true)
	var region := NavigationServer2D.region_create()
	NavigationServer2D.region_set_navigation_polygon(region, navigation)
	NavigationServer2D.region_set_map(region, map)
	_maps[radius] = map
	_regions[radius] = region


func path_from(point: Vector2, radius: float) -> PackedVector2Array:
	prepare(radius)
	var map: RID = _maps[radius]
	if NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array()
	if _boundary.opening_width <= radius * 2.0 + 3.0:
		return PackedVector2Array()
	var target := _boundary.exit_target()
	var path := NavigationServer2D.map_get_path(map, point, target, true)
	if path.is_empty() or path[path.size() - 1].distance_to(target) > 6.0:
		return PackedVector2Array()
	return path


## Spawns must begin on the mesh. Moving enemies may need to return after being pushed off it.
func is_spawn_point(point: Vector2, radius: float) -> bool:
	var path := path_from(point, radius)
	return not path.is_empty() and path[0].distance_to(point) <= 3.0


func _invalidate() -> void:
	var radii := _maps.keys()
	_clear_maps()
	revision += 1
	for radius: float in radii:
		prepare(radius)


func _clear_maps() -> void:
	for region: RID in _regions.values():
		NavigationServer2D.free_rid(region)
	for map: RID in _maps.values():
		NavigationServer2D.free_rid(map)
	_regions.clear()
	_maps.clear()
