## The attacks one fighter has access to.
##
## Per-character frame data is scaled by SPEED at runtime rather than authored
## four times over, so a single shared moveset still produces a sluggish bruiser
## and a snappy sprinter.
class_name MoveSet
extends Resource

## Ordered chain. Each link cancels into the next.
@export var light_chain: Array[AttackDef] = []
@export var heavy: AttackDef
@export var launcher: AttackDef
@export var air_light: AttackDef
@export var air_heavy: AttackDef
@export var grab: AttackDef


func light(index: int) -> AttackDef:
	if light_chain.is_empty():
		return null
	return light_chain[clampi(index, 0, light_chain.size() - 1)]


func has_light_follow_up(index: int) -> bool:
	return index + 1 < light_chain.size()
