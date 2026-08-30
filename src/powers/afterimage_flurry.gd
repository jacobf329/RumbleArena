## Jinsoku's signature: dash through them and leave yourself behind.
##
## The dash is the attack; the decoy is the reason it is hers. A STRENGTH 2,
## TOUGHNESS 2 character cannot stand in front of anybody, so her power is not
## about winning the exchange -- it is about not being where the answer lands.
class_name AfterimageFlurry
extends Power

@export var decoy_scene: PackedScene
## How far the dash carries her past where she started.
@export var dash_distance: float = 4.2
## Vertical clearance kept while dashing, so she does not end up inside a ledge.
@export var dash_clearance: float = 0.9


func activate(fighter: Node3D) -> void:
	var from: Vector3 = fighter.global_position
	_leave_decoy(fighter, from)

	# Dashes to the last clear point rather than straight to the full distance,
	# so a wall stops her instead of putting her inside it.
	var facing: Vector3 = fighter.get_facing_direction()
	fighter.global_position = _clear_point(fighter, from, facing)
	fighter.velocity = facing * (dash_distance * 0.5)


func _leave_decoy(fighter: Node3D, at: Vector3) -> void:
	if decoy_scene == null:
		return
	var root := _interactable_root(fighter)
	if root == null:
		return

	var decoy: Node3D = decoy_scene.instantiate()
	root.add_child(decoy)
	decoy.global_position = at
	var slot = fighter.get("slot")
	var colour: Color = slot.color if slot != null else Color.WHITE
	decoy.setup(fighter, colour)


## Walks the dash in steps and stops at the last one with room to stand, using
## the same physics the fighter moves through rather than a guess about the
## arena's shape.
func _clear_point(fighter: Node3D, from: Vector3, facing: Vector3) -> Vector3:
	var space := fighter.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Layers.WORLD | Layers.BARRIER
	query.exclude = [fighter.get_rid()]

	var best := from
	var steps := 7
	for i in range(1, steps + 1):
		var candidate := from + facing * (dash_distance * float(i) / float(steps))
		query.from = best + Vector3.UP * dash_clearance
		query.to = candidate + Vector3.UP * dash_clearance
		if not space.intersect_ray(query).is_empty():
			break
		best = candidate
	return best


func _interactable_root(fighter: Node3D) -> Node:
	var arena := fighter.get_tree().get_first_node_in_group(&"arena") as Arena
	return arena.interactable_root() if arena != null else fighter.get_parent()
