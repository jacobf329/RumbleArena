## The damage, knockback and hitstun formulas, in one place.
##
## STRENGTH scales what you deal; TOUGHNESS scales what you shrug off. They are
## deliberately kept on separate sides of the equation -- damage answers to the
## attacker alone, while knockback and hitstun are the contest between the two.
## That keeps a STRENGTH 5 bruiser terrifying without making a TOUGHNESS 5 wall
## simply immune to a STRENGTH 1 hacker.
class_name CombatMath

## Fraction of damage that gets through a block.
const BLOCK_DAMAGE_SCALE := 0.25
## Blocked hits still shove you, just less.
const BLOCK_KNOCKBACK_SCALE := 0.45
## Blockstun is shorter than hitstun, so blocking buys you your turn back.
const BLOCK_STUN_SCALE := 0.6
## Stamina burned per point of damage absorbed on block.
const BLOCK_STAMINA_PER_DAMAGE := 1.6

## Damage and knockback bonus for a strike launched on beat, before flow.
const ON_BEAT_STRIKE_BONUS := 0.25
## Each consecutive on-beat link adds this much on top, up to MAX_FLOW.
const FLOW_STRIKE_BONUS := 0.09
const MAX_FLOW := 4
## Startup multiplier for a move cancelled into on beat. Rhythm is rewarded in
## speed as well as damage, so a clean chain visibly outruns a mashed one.
const ON_BEAT_STARTUP_SCALE := 0.72


## Damage/knockback multiplier for a strike, given how it was launched.
static func strike_scale(on_beat: bool, flow: int) -> float:
	if not on_beat:
		return 1.0
	return 1.0 + ON_BEAT_STRIKE_BONUS + FLOW_STRIKE_BONUS * mini(flow, MAX_FLOW)

## Speed above which landing while still stunned puts you on the floor.
const KNOCKDOWN_SPEED := 11.0
## Impact speed into a wall that causes a splat.
const WALL_SPLAT_SPEED := 12.0
const WALL_SPLAT_BONUS_TICKS := 18


static func offense(strength: int) -> float:
	return 0.7 + 0.12 * strength


static func defense(toughness: int) -> float:
	return 0.7 + 0.12 * toughness


static func damage(attack: AttackDef, attacker: CharacterDef) -> float:
	return attack.damage * offense(attacker.stat_strength)


static func knockback_speed(attack: AttackDef, attacker: CharacterDef, victim: CharacterDef) -> float:
	return attack.knockback * offense(attacker.stat_strength) / defense(victim.stat_toughness)


## Clamped, because a combo that only connects against one half of the roster is
## a balance problem rather than a feel one.
static func hitstun_ticks(attack: AttackDef, attacker: CharacterDef, victim: CharacterDef) -> int:
	var ratio := offense(attacker.stat_strength) / defense(victim.stat_toughness)
	return maxi(1, roundi(attack.ticks_hitstun * clampf(ratio, 0.7, 1.4)))


## Startup and recovery answer to SPEED; active frames never do, so a hitbox is
## the same size in time for everyone and only the commitment around it changes.
static func scale_ticks(ticks: int, scale: float) -> int:
	return maxi(1, roundi(ticks * scale))


static func build_hit(attack: AttackDef, attacker: Node3D, attacker_def: CharacterDef,
		victim_def: CharacterDef, facing: Vector3, at: Vector3, blocked: bool,
		strike_scale := 1.0) -> HitResult:
	var result := HitResult.new()
	result.attacker = attacker
	result.attack = attack
	result.position = at
	result.blocked = blocked

	result.damage = damage(attack, attacker_def) * strike_scale
	var speed := knockback_speed(attack, attacker_def, victim_def) * strike_scale
	var stun := hitstun_ticks(attack, attacker_def, victim_def)

	if blocked:
		result.damage *= BLOCK_DAMAGE_SCALE
		speed *= BLOCK_KNOCKBACK_SCALE
		stun = maxi(1, roundi(stun * BLOCK_STUN_SCALE))

	result.knockback = attack.knockback_direction(facing) * speed
	result.hitstun_ticks = stun
	result.hitstop_ticks = attack.ticks_hitstop
	return result
