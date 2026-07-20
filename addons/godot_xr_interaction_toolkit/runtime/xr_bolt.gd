extends RigidBody3D

## A blaster projectile: a fast little bolt that flies from the muzzle, knocks
## physics targets around, and frees itself after a moment so bolts don't pile up.

@export var lifetime := 3.0


func _ready() -> void:
	get_tree().create_timer(lifetime).timeout.connect(queue_free)
