## A named special move.
##
## Extends AttackDef rather than sitting beside it, so a power inherits frame
## data, hitboxes, animation alignment and cancel rules for free and only has to
## describe what makes it special. A power that is purely a strike needs no
## script at all beyond its numbers.
class_name Power
extends AttackDef

@export_group("Power")
@export var power_cost: float = 40.0
@export var cooldown_seconds: float = 5.0


## Called once, as the move goes active and before its hitbox resolves, so a
## power that repositions the fighter still lands its own strike.
func activate(_fighter: Node3D) -> void:
	pass
