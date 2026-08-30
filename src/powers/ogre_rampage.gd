## Kurogane's ultimate: for a while, small hits simply do not stop him.
##
## Armour rather than invulnerability. He still takes the damage; he just does
## not flinch, so chip and spacing stop working on him and the only answer is to
## hit him hard enough to break through.
class_name OgreRampage
extends Power

@export var duration_ticks: int = 480
## Hits doing less than this are absorbed without hitstun.
@export var armour_threshold: float = 12.0
@export var damage_bonus: float = 0.3


func activate(fighter: Node3D) -> void:
	fighter.apply_rampage(duration_ticks, armour_threshold, damage_bonus)
