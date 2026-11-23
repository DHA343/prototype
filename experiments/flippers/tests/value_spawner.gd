extends EnemySpawner

var episode_seed: int = 1
var spawn_ordinal: int = 0


func _spawn_one() -> void:
	# Isolate each spawn's uniform draws from presentation randomness and prior attempts.
	seed(episode_seed + spawn_ordinal * 1000003)
	spawn_ordinal += 1
	super._spawn_one()
