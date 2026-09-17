class_name HitScaleReaction
extends Node

@export_range(0.0, 1.0, 0.01) var scale_pull: float = 0.25

@export_group("Spring", "spring_")
@export_range(1.0, 1000.0, 1.0) var spring_stiffness: float = 200.0
@export_range(0.0, 100.0, 0.1) var spring_damping: float = 10.0

var _spring: ScaleSpring = ScaleSpring.new()

@onready var _visual_root: Node2D = $"../VisualRoot"


func _ready() -> void:
	_spring.settle()
	_visual_root.scale = Vector2.ONE
	set_process(false)


func _process(delta: float) -> void:
	_spring.update(delta)

	if _spring.is_settled():
		_spring.settle()
		_visual_root.scale = Vector2.ONE
		set_process(false)
		return

	_visual_root.scale = Vector2.ONE * _spring.value


func play() -> void:
	_spring.stiffness = spring_stiffness
	_spring.damping = spring_damping
	_spring.start(1.0 + scale_pull)

	_visual_root.scale = Vector2.ONE * _spring.value
	set_process(true)
