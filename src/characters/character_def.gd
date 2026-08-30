## Everything that makes one ninja different from another, as data.
##
## Adding a character should mean authoring a .tres and (later) a power script,
## never editing fighter.gd. If a new ninja needs a change in the fighter class,
## the abstraction has failed -- see docs/GAME_DESIGN.md section 9.
##
## The derived getters below are the whole of pillar P1 at the movement layer:
## a STRENGTH 5 / SPEED 2 bruiser and a SPEED 5 sprinter do not share a feel,
## and neither number was authored by hand -- both fall out of the stat block.
class_name CharacterDef
extends Resource

@export var display_name: String = "Unnamed"
@export var epithet: String = ""
@export_multiline var concept: String = ""

@export_group("Stats", "stat_")
@export_range(1, 5) var stat_strength: int = 3
@export_range(1, 5) var stat_speed: int = 3
@export_range(1, 5) var stat_agility: int = 3
@export_range(1, 5) var stat_tech: int = 3
@export_range(1, 5) var stat_focus: int = 3
@export_range(1, 5) var stat_toughness: int = 3

@export_group("Combat")
## The attacks this fighter has. Frame data is shared and then scaled by SPEED,
## so one authored moveset still produces a sluggish bruiser and a snappy
## sprinter -- see get_attack_speed_scale().
@export var move_set: MoveSet

@export_group("Presentation")
@export var body_color: Color = Color.WHITE


## The permission check behind every interactable in the game.
func get_stat(type: Stats.Type) -> int:
	match type:
		Stats.Type.STRENGTH: return stat_strength
		Stats.Type.SPEED: return stat_speed
		Stats.Type.AGILITY: return stat_agility
		Stats.Type.TECH: return stat_tech
		Stats.Type.FOCUS: return stat_focus
		Stats.Type.TOUGHNESS: return stat_toughness
	return 0


func meets(type: Stats.Type, tier: int) -> bool:
	return get_stat(type) >= tier


# --- Derived movement, all driven by the stat block ---

func get_max_speed() -> float:
	return 6.0 + stat_speed * 1.1


func get_acceleration() -> float:
	return 45.0 + stat_speed * 12.0


## Heavier fighters slide; light quick ones stop on a dime.
func get_ground_friction() -> float:
	return 60.0 - stat_strength * 4.0 + stat_speed * 4.0


func get_jump_height() -> float:
	return 1.9 + stat_agility * 0.32


func get_air_control() -> float:
	return 0.30 + stat_agility * 0.09


## The first permission check a player ever meets: double jump is AGILITY 3+.
## Kurogane simply cannot, and finding that out is how you learn the system.
func get_extra_jumps() -> int:
	return 1 if stat_agility >= 3 else 0


func get_dash_speed() -> float:
	return 13.0 + stat_speed * 2.0


func get_dash_duration() -> float:
	return 0.14 + stat_speed * 0.008


func get_dash_cooldown() -> float:
	return 0.85 - stat_speed * 0.09


func get_turn_speed() -> float:
	return 8.0 + stat_speed * 1.5


func get_max_health() -> float:
	return 80.0 + stat_toughness * 20.0


func get_max_power() -> float:
	return 60.0 + stat_focus * 20.0


func get_max_stamina() -> float:
	return 60.0 + stat_toughness * 10.0


## Multiplier on attack startup and recovery. Active frames are never scaled, so
## a hitbox is live for the same length of time for everyone and only the
## commitment wrapped around it differs.
func get_attack_speed_scale() -> float:
	return 1.35 - 0.12 * stat_speed


## Heaviest mass class this fighter can lift or break. Used from M3 onward.
func get_lift_class() -> int:
	return stat_strength


func get_stat_line() -> String:
	return "STR %d  SPD %d  AGI %d  TECH %d  FOC %d  TGH %d" % [
		stat_strength, stat_speed, stat_agility,
		stat_tech, stat_focus, stat_toughness,
	]
