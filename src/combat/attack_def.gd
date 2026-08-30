## Frame data for one attack.
##
## Everything a move does lives here as data, so tuning combat means editing a
## .tres rather than editing code. Timings are in physics ticks at 60 Hz.
class_name AttackDef
extends Resource

@export var display_name: String = "Attack"

@export_group("Timing", "ticks_")
## Wind-up. Longer startup is the price of a stronger move.
@export var ticks_startup: int = 5
## Frames the hitbox is live.
@export var ticks_active: int = 3
## Commitment after the hitbox closes; this is what makes a whiff punishable.
@export var ticks_recovery: int = 9

@export_group("Damage")
@export var damage: float = 4.0
## Metres per second imparted to the victim, before the STRENGTH/TOUGHNESS scale.
@export var knockback: float = 4.0
## Degrees above horizontal. 90 launches straight up; negative spikes downward.
@export var launch_angle: float = 12.0
## How long the victim is locked out of their own control.
@export var ticks_hitstun: int = 14
## Freeze applied to both fighters on connect. The single biggest source of
## impact when there is no animation to sell the hit.
@export var ticks_hitstop: int = 4
@export var power_gain: float = 6.0

@export_group("Movement")
## Forward lunge applied at the moment the hitbox opens.
@export var step_forward: float = 0.0
## Air moves that arrest a fall read as far more deliberate than ones that don't.
@export var halts_fall: bool = false

@export_group("Hitbox")
@export var hitbox_size: Vector3 = Vector3(1.2, 1.2, 1.6)
## Offset from the fighter's feet, in the fighter's own frame (-Z is forward).
@export var hitbox_offset: Vector3 = Vector3(0, 1.0, -1.0)

@export_group("Projectile")
## Launches a fireball as the hitbox opens. The light chain's finisher uses
## this, so punch-punch-kick ends in a projectile.
@export var launches_fireball: bool = false
@export var fireball_power_cost: float = 30.0
@export var fireball_damage: float = 11.0
@export var fireball_speed: float = 13.0
@export var fireball_knockback: float = 8.0

@export_group("Grab")
## Seizes the victim rather than striking them: ignores blocking, holds them
## through the animation, then throws them. Grab beats block, block beats
## strike, strike beats grab.
@export var is_grab: bool = false
## Tick, measured from the start of the move, at which the victim is released.
@export var grab_release_tick: int = 26
@export var grab_throw_speed: float = 16.0
@export var grab_damage: float = 13.0
@export var grab_launch_angle: float = 34.0

@export_group("Animation")
## Clip in the shared ninja library. Frame data owns gameplay timing; the clip
## is scaled to fit it, never the other way round.
@export var animation: StringName = &""
## Slice of the clip this move uses, and the moment within it that contact
## happens. Playback is scaled so `animation_impact` lands on the active frames.
@export var animation_start: float = 0.0
@export var animation_impact: float = 0.0
@export var animation_end: float = 0.0

@export_group("Rhythm")
## Half-width, in ticks, of the sweet spot around the moment this move becomes
## cancellable. Input landing inside it is "on beat": the follow-up comes out
## faster and hits harder. Mashing early still combos, it just earns nothing.
@export var rhythm_window_ticks: int = 7

@export_group("Cancelling")
## Tick, measured from the end of the active window, at which this move may be
## cancelled into its follow-up.
@export var cancel_window_start: int = 2
## When true the follow-up is only available if this move actually connected,
## so whiffing a confirm costs you the full recovery.
@export var cancel_requires_hit: bool = false


func total_ticks() -> int:
	return ticks_startup + ticks_active + ticks_recovery


## Seconds of clip between the slice start and the moment of contact.
func animation_wind_up() -> float:
	return maxf(animation_impact - animation_start, 0.0)


## Seconds of clip after contact.
func animation_follow_through() -> float:
	return maxf(animation_end - animation_impact, 0.0)


func has_animation() -> bool:
	return animation != &"" and animation_end > animation_start


func active_start() -> int:
	return ticks_startup


func active_end() -> int:
	return ticks_startup + ticks_active


## Unit direction the victim is sent, given the attacker's facing.
func knockback_direction(facing: Vector3) -> Vector3:
	var radians := deg_to_rad(launch_angle)
	return (facing * cos(radians) + Vector3.UP * sin(radians)).normalized()
