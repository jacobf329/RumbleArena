## A committed burst along a direction locked in at the moment of the press.
##
## Gravity is suspended for the duration so a ground dash reads as a flat
## lunge rather than a hop, and so an air dash gives a real recovery option.
class_name DashState
extends FighterState

var _time_left := 0.0
var _direction := Vector3.ZERO


func get_id() -> StringName:
	return DASH


func enter(_previous: StringName) -> void:
	_direction = fighter.get_move_direction()
	if _direction == Vector3.ZERO:
		_direction = fighter.get_facing_direction()
	_time_left = fighter.character_def.get_dash_duration()
	fighter.start_dash_cooldown()
	fighter.snap_facing(_direction)


func physics_update(delta: float) -> StringName:
	_time_left -= delta

	var speed: float = fighter.character_def.get_dash_speed()
	fighter.velocity.x = _direction.x * speed
	fighter.velocity.z = _direction.z * speed
	fighter.velocity.y = 0.0

	if _time_left > 0.0:
		return STAY

	# Bleed the dash down to run speed so it boosts into a run instead of
	# stopping dead or launching the fighter across the arena.
	var max_speed: float = fighter.character_def.get_max_speed()
	fighter.velocity.x = _direction.x * max_speed
	fighter.velocity.z = _direction.z * max_speed

	if not fighter.is_on_floor():
		return AIR
	return RUN if fighter.get_move_direction() != Vector3.ZERO else IDLE
