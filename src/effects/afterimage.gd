## Jinsoku's decoy: a standing copy of her that bursts when it is struck.
##
## Extends Breakable rather than inventing a new kind of target, so it is
## already something an attack's hitbox query finds and already has health to
## take off. What makes it a decoy rather than scenery is that hitting it costs
## you: the burst is the punishment for swinging at the wrong Jinsoku.
##
## It is deliberately fragile and short-lived. A decoy that survived a round of
## pressure would be a free extra body for the character who least deserves one;
## the value is the half-second of hesitation, not the wall.
class_name Afterimage
extends Breakable

## Who it is pretending to be. Never hurt by its own burst.
var owner_fighter: Node3D

@export var lifetime_ticks: int = 150
@export var burst_radius: float = 2.6
@export var burst_damage: float = 8.0
@export var burst_knockback: float = 9.0
@export var burst_hitstun: int = 26

@onready var _visual: FighterVisual = $Visual

var _ticks_left: int


func _ready() -> void:
	super()
	# Anyone can pop it, whatever their STRENGTH: it is an illusion, not a wall,
	# and a decoy that a weak character could not clear would read as a bug.
	break_tier = 1
	display_name = "Afterimage"
	add_to_group(&"afterimages")
	_ticks_left = lifetime_ticks


## Called by the power, because the decoy has to know both whose colour to wear
## and who not to hit.
func setup(fighter: Node3D, colour: Color) -> void:
	owner_fighter = fighter
	if not is_node_ready():
		await ready
	_visual.set_player_colour(colour)
	global_rotation.y = fighter.global_rotation.y


func _physics_process(_delta: float) -> void:
	_ticks_left -= 1
	if _visual != null:
		# Fades out over its last half second, so it reads as expiring rather
		# than blinking out of existence.
		_visual.set_ghost_alpha(0.55 * minf(float(_ticks_left) / 30.0, 1.0))
	if _ticks_left <= 0:
		_expire()


func _process(_delta: float) -> void:
	if _visual != null:
		_visual.play_locomotion(0.0, false)


## Struck: this is the whole point of the thing.
func _shatter() -> void:
	broken.emit(global_position)
	_burst()
	queue_free()


## Simply ran out of time. No burst -- the decoy has to be hit to punish, or it
## would be a delayed area attack you could set and walk away from.
func _expire() -> void:
	queue_free()


func _burst() -> void:
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var victim := node as Fighter
		if victim == null or victim == owner_fighter or victim.is_eliminated:
			continue
		if victim.is_invulnerable():
			continue
		var offset := victim.global_position - global_position
		if offset.length() > burst_radius:
			continue

		var result := HitResult.new()
		result.attacker = owner_fighter
		result.damage = burst_damage
		result.knockback = _away_from(offset) * burst_knockback
		result.hitstun_ticks = burst_hitstun
		result.hitstop_ticks = 6
		result.position = victim.global_position + Vector3.UP
		victim.take_hit(result)


## Outward and slightly up. Straight out would slide people along the floor;
## straight up would juggle everyone in range for free.
func _away_from(offset: Vector3) -> Vector3:
	var flat := Vector3(offset.x, 0.0, offset.z)
	if flat.length_squared() < 0.01:
		flat = Vector3.FORWARD
	return (flat.normalized() + Vector3.UP * 0.55).normalized()
