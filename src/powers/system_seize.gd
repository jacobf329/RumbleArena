## Null's ultimate: every turret in the arena answers to her at once.
##
## The clearest statement of why a STRENGTH 1 character is worth playing. She
## cannot win a trade with anybody, so instead she takes the room.
class_name SystemSeize
extends Power


func activate(fighter: Node3D) -> void:
	for node in fighter.get_tree().get_nodes_in_group(&"turrets"):
		var turret := node as HackableTurret
		if turret != null:
			turret.seize_by(fighter)
