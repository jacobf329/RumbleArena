## Yamabuki's signature: a line to the nearest high ground, and a ride to it.
##
## Written against the arena's geometry rather than against its Climbable nodes.
## Keying it to climbables would have made the power a property of how an arena
## was decorated -- the Proving Ground has exactly one climbable wall, so she
## would have had one place to grapple in the whole level. Anything she can
## stand on is a valid anchor instead, which makes the power a reading of the
## room and gives AGILITY 5 a verb everywhere.
class_name GrappleLine
extends Power

## How far the line reaches, horizontally.
@export var reach: float = 11.0
## Ledges lower than this are not worth a grapple; she can just jump.
@export var minimum_rise: float = 1.4
## How far above her the line will still bite.
@export var maximum_rise: float = 7.5
## Directions sampled either side of where she is facing, in degrees.
@export var sweep_degrees: float = 55.0
## Time the arc takes. Short enough to be a movement tool, long enough to see.
@export var travel_seconds: float = 0.42


func activate(fighter: Node3D) -> void:
	var anchor := _find_anchor(fighter)
	if anchor == Vector3.INF:
		return  # A whiff into recovery, same as a Blink Strike with nobody near.
	# apply_launch rather than setting velocity: attack drift would otherwise eat
	# the arc within two ticks of the move that created it.
	fighter.apply_launch(_arc_to(fighter, anchor), ceili(travel_seconds * 60.0) + 6)
	fighter.snap_facing(Vector3(anchor.x - fighter.global_position.x, 0.0,
		anchor.z - fighter.global_position.z))


## The highest standable point within reach, sampled in a fan ahead of her.
## Returns Vector3.INF when there is nothing worth grappling to.
func _find_anchor(fighter: Node3D) -> Vector3:
	var space := fighter.get_world_3d().direct_space_state
	var origin: Vector3 = fighter.global_position
	var facing: Vector3 = fighter.get_facing_direction()

	var best := Vector3.INF
	var best_rise := minimum_rise

	for turn in [0.0, -0.5, 0.5, -1.0, 1.0]:
		var direction := facing.rotated(Vector3.UP, deg_to_rad(sweep_degrees * turn))
		for step in range(2, 9):
			var distance := reach * float(step) / 8.0
			var probe := origin + direction * distance
			var surface := _surface_height(space, fighter, probe, origin.y)
			if is_nan(surface):
				continue
			var rise := surface - origin.y
			if rise <= best_rise or rise > maximum_rise:
				continue
			# Only if she could actually stand there.
			if not _has_headroom(space, fighter, Vector3(probe.x, surface, probe.z)):
				continue
			best_rise = rise
			best = Vector3(probe.x, surface, probe.z)
	return best


## Drops a ray from above the probe to find what she would land on. NAN rather
## than a height when there is nothing there, so a hole in the floor is not read
## as ground at y = 0. (NAN rather than null because a function that returns
## either cannot be given a return type, and an untyped return here would spread
## Variant through every caller.)
func _surface_height(space: PhysicsDirectSpaceState3D, fighter: Node3D,
		probe: Vector3, from_y: float) -> float:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Layers.WORLD
	query.exclude = [fighter.get_rid()]
	query.from = Vector3(probe.x, from_y + maximum_rise + 1.0, probe.z)
	query.to = Vector3(probe.x, from_y - 1.0, probe.z)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return (hit["position"] as Vector3).y


func _has_headroom(space: PhysicsDirectSpaceState3D, fighter: Node3D, landing: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = Layers.WORLD
	query.exclude = [fighter.get_rid()]
	query.from = landing + Vector3.UP * 0.2
	query.to = landing + Vector3.UP * 1.9
	return space.intersect_ray(query).is_empty()


## The launch velocity that puts her on the anchor, solved against the gravity
## she actually falls under rather than a constant, so tuning gravity does not
## silently break the power.
func _arc_to(fighter: Node3D, anchor: Vector3) -> Vector3:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)
	var offset := anchor - fighter.global_position
	var flat := Vector3(offset.x, 0.0, offset.z)

	var horizontal := flat / travel_seconds
	# A little past the lip, so she arrives on top of the ledge rather than into
	# its edge and slides back off.
	var rise := offset.y + 0.6
	var vertical := rise / travel_seconds + 0.5 * gravity * travel_seconds
	return Vector3(horizontal.x, vertical, horizontal.z)
