extends Node

enum Mode {
	SPARK,
	RING,
	BOTH,
	OFF,
}

const IMPACT: PackedScene = preload("res://experiments/orb_impact/impact.tscn")

@export var mode: Mode = Mode.SPARK

var _slow_motion: bool = false
var _original_time_scale: float = 1.0

@onready var _game: Main = $Main
@onready var _effects: Node2D = $Impacts
@onready var _status: Label = $Controls/Panel/Status


func _ready() -> void:
	_original_time_scale = Engine.time_scale
	_game.orb.sweep_hit.hurtbox_detected.connect(_on_hurtbox_detected)
	_update_status()


func _exit_tree() -> void:
	Engine.time_scale = _original_time_scale


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_1:
			mode = Mode.SPARK
		KEY_2:
			mode = Mode.RING
		KEY_3:
			mode = Mode.BOTH
		KEY_0:
			mode = Mode.OFF
		KEY_4:
			_slow_motion = not _slow_motion
			Engine.time_scale = _original_time_scale * (0.25 if _slow_motion else 1.0)
		_:
			return
	_update_status()
	get_viewport().set_input_as_handled()


func _on_hurtbox_detected(hurtbox: Hurtbox, direction: Vector2) -> void:
	if mode == Mode.OFF:
		return
	# The experiment uses the existing circular enemy surface, including lethal hits.
	var collision_shape := hurtbox.get_node("CollisionShape2D") as CollisionShape2D
	var circle := collision_shape.shape as CircleShape2D
	var contact := hurtbox.global_position - direction * circle.radius
	var impact: Node2D = IMPACT.instantiate()
	_effects.add_child(impact)
	impact.global_position = contact
	impact.play(direction, _game.orb.movement.velocity.length(), mode != Mode.RING, mode != Mode.SPARK)


func _update_status() -> void:
	var names: Array[String] = ["SPARK", "RING", "SPARK + RING", "OFF"]
	_status.text = "IMPACT LAB  /  %s  /  %s\n1 Spark   2 Ring   3 Both   0 Off   4 Slow motion" % [
		names[mode], "0.25x" if _slow_motion else "1x"
	]
