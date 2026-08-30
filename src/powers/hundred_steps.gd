## Jinsoku's ultimate: for a while, she is simply faster than the game.
##
## The deliberate opposite of Kurogane's Ogre Rampage. His makes hits stop
## mattering; hers makes the clock stop mattering. Both are "you cannot deal
## with me for ten seconds", but one is answered by hitting harder and the other
## by covering space -- which is what keeps two buff ultimates from being the
## same ultimate.
class_name HundredSteps
extends Power

@export var duration_ticks: int = 420
## Multiplier on top speed while it lasts.
@export var speed_bonus: float = 0.55
## How much of an attack's startup and recovery is cut. Her damage is untouched:
## a TOUGHNESS 2 character being allowed to hit harder as well as faster is how
## a mobility ultimate quietly becomes the best damage ultimate.
@export var attack_bonus: float = 0.3


func activate(fighter: Node3D) -> void:
	fighter.apply_haste(duration_ticks, speed_bonus, attack_bonus)
