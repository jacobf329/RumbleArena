## A wall surface a sufficiently agile fighter can go up.
##
## The AGILITY gate's own verb. Double jumping already keys off AGILITY 3, so
## climbing is pitched at 4 to give the one genuinely acrobatic character
## something nobody else can do, rather than a taller version of what three of
## them already have.
class_name Climbable
extends Interactable

## World height of the surface to mantle onto at the top.
@export var top_y: float = 5.0
## How far off the wall the fighter is held while climbing.
@export var hug_distance: float = 0.45


func _ready() -> void:
	super()
	verb = "Climb"
	display_name = "Wall"
	required_stat = Stats.Type.AGILITY
	required_tier = 4


## The direction away from the wall, taken from the node's own +Z so a surface
## can simply be rotated into place in the editor.
func outward_normal() -> Vector3:
	var normal := global_transform.basis.z
	normal.y = 0.0
	return normal.normalized()


## Nearest point on the wall plane, held `hug_distance` clear of it.
func anchor_for(position: Vector3) -> Vector3:
	var normal := outward_normal()
	var to_position := position - global_position
	var depth := to_position.dot(normal)
	return position - normal * (depth - hug_distance)


func is_above_top(position: Vector3) -> bool:
	return position.y >= top_y - 0.15


## Climbing is entered by the state machine rather than by an instant effect,
## so `use` only reports that the fighter qualifies.
func use(fighter: Node3D) -> bool:
	return can_use(fighter)
