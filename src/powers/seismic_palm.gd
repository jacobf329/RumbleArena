## Kurogane's signature: a shockwave that cracks the floor.
##
## The damage is ordinary frame data. What makes it his is the debris left
## behind -- the arena gets more to throw every time he uses it, which is only
## worth anything to the fighter who can lift the heavy things.
class_name SeismicPalm
extends Power

@export var debris_scene: PackedScene
@export var debris_count: int = 2
@export var debris_spread: float = 1.6


func activate(fighter: Node3D) -> void:
	if debris_scene == null:
		return
	var arena := _interactable_root(fighter)
	if arena == null:
		return
	var facing: Vector3 = fighter.get_facing_direction()
	var centre: Vector3 = fighter.global_position + facing * 1.8

	for i in debris_count:
		var piece: Node3D = debris_scene.instantiate()
		arena.add_child(piece)
		var angle := TAU * float(i) / float(maxi(debris_count, 1))
		piece.global_position = centre \
			+ Vector3(cos(angle), 0.0, sin(angle)) * debris_spread + Vector3.UP * 0.4


func _interactable_root(fighter: Node3D) -> Node:
	var arena := fighter.get_tree().get_first_node_in_group(&"arena") as Arena
	return arena.interactable_root() if arena != null else fighter.get_parent()
