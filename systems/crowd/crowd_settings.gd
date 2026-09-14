class_name CrowdSettings
extends Resource

@export_range(0.0, 100.0, 1.0, "suffix:unit") var radius: float = 16.0:
	set(value):
		radius = maxf(value, 0.0)
		avoidance_radius = maxf(avoidance_radius, radius)

@export_range(0.0, 100.0, 1.0, "suffix:unit") var avoidance_radius: float = 22.0:
	set(value):
		avoidance_radius = maxf(value, radius)

@export_range(0.0, 10.0, 0.1) var response: float = 1.0:
	set(value):
		response = clampf(value, 0.0, 10.0)
