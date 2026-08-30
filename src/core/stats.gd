## The six stats that define a fighter.
##
## Stats are not just damage multipliers -- they are permission checks on the
## world. Every interactable declares a required stat and tier; a fighter may
## use it only if their rating meets it. See docs/GAME_DESIGN.md section 3.
class_name Stats
extends RefCounted

enum Type {
	STRENGTH,  ## Damage and knockback; mass class of objects you can lift.
	SPEED,     ## Move speed, dash charges, attack startup.
	AGILITY,   ## Air control and jump count; wall-climb and ledge grab.
	TECH,      ## Hacking terminals, turrets, doors and traps.
	FOCUS,     ## Power meter size and regen; power duration and range.
	TOUGHNESS, ## Max health, hitstun resistance, armor frames.
}

const MIN_TIER := 1
const MAX_TIER := 5

const DISPLAY_NAMES := {
	Type.STRENGTH: "STRENGTH",
	Type.SPEED: "SPEED",
	Type.AGILITY: "AGILITY",
	Type.TECH: "TECH",
	Type.FOCUS: "FOCUS",
	Type.TOUGHNESS: "TOUGHNESS",
}

static func display_name(type: Type) -> String:
	return DISPLAY_NAMES.get(type, "?")
