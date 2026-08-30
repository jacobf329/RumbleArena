## A ceiling turret that answers to whoever hacked it last.
##
## The TECH gate made concrete. A hacker who cannot win a straight fight can
## still turn the room against everyone else, which is what makes a STRENGTH 1
## character worth playing.
##
## Hacked at range rather than by touch: the turret hangs from the ceiling, and
## making the hacker climb up to press a button on it would be both bad fiction
## and unreachable for the one character meant to use it. Its detection volume is
## therefore much larger than its housing.
class_name HackableTurret
extends Interactable

const PROJECTILE_SPEED := 17.0

@export var fire_interval := 1.0
@export var engage_range := 15.0
@export var projectile_damage := 9.0
@export var idle_colour := Color(0.45, 0.47, 0.52)

## Whoever hacked it. Null means dormant -- an unhacked turret does nothing,
## so the arena is not hostile until somebody makes it hostile.
var controller: Node3D = null

var _cooldown := 0.0

@onready var _light: MeshInstance3D = $Light


func _ready() -> void:
	super()
	verb = "Hack"
	display_name = "Turret"
	required_stat = Stats.Type.TECH
	required_tier = 3
	_set_light(idle_colour)


## Already yours is not worth a prompt; someone else's very much is.
func is_offered(fighter: Node3D) -> bool:
	return controller != fighter


func use(fighter: Node3D) -> bool:
	if not can_use(fighter):
		return false
	controller = fighter
	var slot = fighter.get("slot")
	_set_light(slot.color if slot != null else Color.WHITE)
	_cooldown = fire_interval * 0.5
	return true


func _physics_process(delta: float) -> void:
	if controller == null or not is_instance_valid(controller):
		controller = null
		return

	_cooldown -= delta
	if _cooldown > 0.0:
		return

	var target := _nearest_enemy()
	if target == null:
		return

	_cooldown = fire_interval
	var muzzle := global_position + Vector3.DOWN * 0.4
	var slot = controller.get("slot")
	Projectile.spawn(get_parent(), muzzle,
		(target.global_position + Vector3.UP * 1.0) - muzzle,
		PROJECTILE_SPEED, projectile_damage, controller,
		slot.color if slot != null else Color.WHITE)


func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_distance := engage_range
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var fighter := node as Node3D
		if fighter == null or fighter == controller or not is_instance_valid(fighter):
			continue
		var distance := global_position.distance_to(fighter.global_position)
		if distance < best_distance:
			best_distance = distance
			best = fighter
	return best


func _set_light(colour: Color) -> void:
	if _light == null:
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	material.emission_energy_multiplier = 1.6
	_light.material_override = material
