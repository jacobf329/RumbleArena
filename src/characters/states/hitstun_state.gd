## Being hit: no control, carried by the knockback.
class_name HitstunState
extends FighterState

## Grace before a landing can knock you down, so a grounded hit does not put you
## on the floor on the very tick it lands.
const MIN_TICKS_BEFORE_KNOCKDOWN := 7

var _ticks_left := 0
var _elapsed := 0
var _splatted := false


func get_id() -> StringName:
	return HITSTUN


func enter(_previous: StringName) -> void:
	_ticks_left = fighter.pending_hitstun
	_elapsed = 0
	_splatted = false


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	fighter.apply_hitstun_drag(delta)

	_ticks_left -= 1
	_elapsed += 1

	# Being slammed into a wall extends the stun -- the free juggle that makes
	# arena geometry worth fighting near.
	if not _splatted and fighter.check_wall_splat():
		_splatted = true
		_ticks_left += CombatMath.WALL_SPLAT_BONUS_TICKS

	if _elapsed >= MIN_TICKS_BEFORE_KNOCKDOWN and fighter.is_on_floor() \
			and fighter.is_knockdown_pending():
		return KNOCKDOWN

	if _ticks_left <= 0:
		if not fighter.is_on_floor():
			return AIR
		return RUN if fighter.get_move_direction() != Vector3.ZERO else IDLE
	return STAY
