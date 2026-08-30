## On the floor. Getting up early is a skill check, not a formality.
class_name KnockdownState
extends FighterState

const DURATION := 36
## Ticks at the start of the knockdown during which a press gets you up early.
const TECH_WINDOW := 14
const TECH_INVULNERABLE := 12
const WAKEUP_INVULNERABLE := 8

var _ticks_left := 0


func get_id() -> StringName:
	return KNOCKDOWN


func enter(_previous: StringName) -> void:
	_ticks_left = DURATION
	fighter.velocity.x = 0.0
	fighter.velocity.z = 0.0
	fighter.set_downed(true)
	fighter.clear_knockdown()


func exit() -> void:
	fighter.set_downed(false)


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	fighter.apply_ground_friction(delta)
	_ticks_left -= 1

	if _ticks_left > DURATION - TECH_WINDOW and fighter.request_tech():
		fighter.grant_invulnerability(TECH_INVULNERABLE)
		return IDLE

	if _ticks_left <= 0:
		# A little invulnerability on wake-up, so being knocked down is not a
		# loop the attacker can simply repeat.
		fighter.grant_invulnerability(WAKEUP_INVULNERABLE)
		return IDLE
	return STAY
