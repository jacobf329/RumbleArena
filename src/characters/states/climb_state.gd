## Clinging to a wall and moving along it.
##
## Gravity is off entirely: a climb that fought gravity would feel like a slow
## fall, and the whole point of the AGILITY gate is that the wall stops being an
## obstacle for the one character who qualifies.
class_name ClimbState
extends FighterState

## Metres per second, before AGILITY scales it.
const BASE_SPEED := 2.2
const SPEED_PER_AGILITY := 0.45
## Sideways movement along the wall is slower than going up it.
const LATERAL_SCALE := 0.7
## Push away from the wall when leaping off.
const LEAP_OUT := 6.0
const LEAP_UP := 9.0
## How far past the lip a mantle puts the fighter, and the small hop it keeps so
## the step up still reads as movement rather than a snap.
const MANTLE_INSET := 1.2
const MANTLE_HOP := 2.0

var _ticks := 0


func get_id() -> StringName:
	return CLIMB


func enter(_previous: StringName) -> void:
	_ticks = 0
	fighter.velocity = Vector3.ZERO
	var wall: Climbable = fighter.climbing
	if wall != null:
		# Face into the wall, which is the opposite of its outward normal.
		fighter.snap_facing(-wall.outward_normal())


func exit() -> void:
	fighter.climbing = null


func physics_update(delta: float) -> StringName:
	var wall: Climbable = fighter.climbing
	if wall == null or not is_instance_valid(wall):
		return AIR

	var input: InputFrame = fighter.get_input()
	_ticks += 1

	# Letting go is always available, and always the fastest way down -- but not
	# on the entry tick: the press that put the fighter on the wall is still a
	# just-pressed edge, and would otherwise take them straight back off it.
	if _ticks > 1 and input.is_just_pressed(InputFrame.Action.INTERACT):
		return AIR

	if input.is_just_pressed(InputFrame.Action.JUMP):
		var out: Vector3 = wall.outward_normal()
		fighter.velocity = out * LEAP_OUT + Vector3.UP * LEAP_UP
		fighter.snap_facing(out)
		return AIR

	var agility: int = fighter.character_def.stat_agility
	var speed := BASE_SPEED + SPEED_PER_AGILITY * agility

	# Stick up climbs; stick left and right slide along the face. Movement is
	# applied as position rather than velocity so the fighter cannot be dragged
	# off the wall by the physics body's own momentum.
	var intent: Vector2 = input.move
	var along: Vector3 = wall.global_transform.basis.x * intent.x * speed * LATERAL_SCALE
	var climb: Vector3 = Vector3.UP * intent.y * speed

	var target: Vector3 = fighter.global_position + (along + climb) * delta
	fighter.global_position = wall.anchor_for(target)
	fighter.velocity = Vector3.ZERO

	if wall.is_above_top(fighter.global_position):
		# Place the fighter on the surface rather than launching them at it. A
		# ballistic pop loses its forward momentum to air drag within a few
		# ticks when the stick is neutral, and drops them back down the wall.
		var forward: Vector3 = -wall.outward_normal()
		fighter.global_position = Vector3(
			fighter.global_position.x,
			wall.top_y + 0.15,
			fighter.global_position.z) + forward * MANTLE_INSET
		fighter.velocity = Vector3.UP * MANTLE_HOP
		return AIR

	return STAY
