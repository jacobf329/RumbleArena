## Null's signature: teleport behind the nearest fighter and hit them.
##
## Deliberately a whiff-into-recovery if nobody is in range, which is what keeps
## a free repositioning tool honest for a character who cannot survive a trade.
class_name BlinkStrike
extends Power

@export var seek_range: float = 9.0
## How far behind the target she lands.
@export var behind_distance: float = 1.1


func activate(fighter: Node3D) -> void:
	var target := _nearest_other(fighter)
	if target == null:
		return

	# Land behind them, relative to the way THEY are facing, so the strike comes
	# from their back rather than wherever the caster happened to be.
	var behind: Vector3 = target.global_position \
		- target.get_facing_direction() * behind_distance
	behind.y = target.global_position.y
	fighter.global_position = behind
	fighter.snap_facing(target.global_position - behind)


func _nearest_other(fighter: Node3D) -> Node3D:
	var best: Node3D = null
	var best_distance := seek_range
	for node in fighter.get_tree().get_nodes_in_group(&"fighters"):
		var other := node as Node3D
		if other == null or other == fighter or not is_instance_valid(other):
			continue
		if other.get("is_eliminated"):
			continue
		var distance := fighter.global_position.distance_to(other.global_position)
		if distance < best_distance:
			best_distance = distance
			best = other
	return best
