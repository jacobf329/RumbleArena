## Something you can pick up, carry and throw.
##
## The signature verb of the whole design: a strength character rips a pillar out
## of the floor and throws it, and a hacker standing in the same spot simply
## cannot. Mass class doubles as the STRENGTH tier required, so "how heavy is it"
## and "who can lift it" are the same number rather than two that can disagree.
class_name Liftable
extends Interactable

## Speed the thrown object travels at, before the thrower's STRENGTH is applied.
const THROW_SPEED := 15.0
## Fraction of a fighter's top speed kept while carrying this.
const CARRY_SPEED_PENALTY := 0.62
const DAMAGE_PER_MASS := 7.0
const KNOCKBACK_PER_MASS := 4.0
## A throw that has travelled this long gives up and drops.
const MAX_FLIGHT := 3.0
## How long a throw ignores the person who threw it.
##
## An object leaves your hands 0.9m in front of your chest, and its 0.7m contact
## sphere still reaches back inside your own hurtbox from there -- so without
## this, every throw hit the thrower on its first or second frame and dropped at
## their feet. The existing test for "a thrown pillar hurts" passed by about
## three centimetres of geometry.
##
## A window rather than a permanent exemption, so a throw straight up still
## lands on the head of whoever launched it.
const THROWER_GRACE := 0.4

signal thrown(by: Node3D)
signal landed()

@export var mass_class: int = 1

var carrier: Node3D = null

var _velocity := Vector3.ZERO
var _flying := false
var _flight_time := 0.0
var _hit_targets: Array = []
var _thrower: Node3D = null
var _home: Node = null

@onready var _body_shape: CollisionShape3D = $Body/Collision


func _ready() -> void:
	super()
	verb = "Lift"
	required_stat = Stats.Type.STRENGTH
	required_tier = mass_class
	_home = get_parent()


func is_offered(_fighter: Node3D) -> bool:
	return carrier == null and not _flying


func use(fighter: Node3D) -> bool:
	if not is_offered(fighter) or not can_use(fighter):
		return false
	carrier = fighter
	# Disable the blocking shape, not the body: a disabled node keeps its
	# collision registered with the physics server.
	_body_shape.set_deferred("disabled", true)
	return true


## Carried objects ride above the carrier's hands rather than being reparented,
## which keeps their transform independent of the model's animation.
func _physics_process(delta: float) -> void:
	if carrier != null and is_instance_valid(carrier):
		global_position = carrier.global_position \
			+ Vector3.UP * 1.9 \
			+ carrier.global_transform.basis * Vector3(0, 0, -0.6)
		rotation.y += delta * 1.4
		return
	if _flying:
		_advance_flight(delta)


func throw_from(fighter: Node3D) -> void:
	var strength := 1.0
	var definition: CharacterDef = fighter.get("character_def")
	if definition != null:
		strength = CombatMath.offense(definition.stat_strength)

	carrier = null
	_thrower = fighter
	_flying = true
	_flight_time = 0.0
	_hit_targets.clear()
	_velocity = fighter.global_transform.basis * Vector3(0, 0.18, -1.0) * THROW_SPEED * strength
	global_position = fighter.global_position + Vector3.UP * 1.4 \
		+ fighter.global_transform.basis * Vector3(0, 0, -0.9)
	thrown.emit(fighter)


func _advance_flight(delta: float) -> void:
	_flight_time += delta
	_velocity.y -= 18.0 * delta
	global_position += _velocity * delta
	rotation.y += delta * 9.0

	for target in _overlapping_fighters():
		if _hit_targets.has(target):
			continue
		if target == _thrower and _flight_time < THROWER_GRACE:
			continue
		_hit_targets.append(target)
		_strike(target)
		_drop()
		return

	if global_position.y <= 0.35 or _flight_time >= MAX_FLIGHT:
		_drop()


func _overlapping_fighters() -> Array:
	var shape := SphereShape3D.new()
	shape.radius = 0.7
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Layers.HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.transform = Transform3D(Basis.IDENTITY, global_position)

	var found: Array = []
	for contact in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var hurtbox := contact["collider"] as Hurtbox
		if hurtbox != null and hurtbox.fighter != null:
			found.append(hurtbox.fighter)
	return found


func _strike(target: Node3D) -> void:
	var result := HitResult.new()
	result.attacker = self
	result.damage = DAMAGE_PER_MASS * mass_class
	result.hitstun_ticks = 20 + 4 * mass_class
	result.hitstop_ticks = 7
	result.position = global_position
	result.knockback = _velocity.normalized() * (KNOCKBACK_PER_MASS * mass_class) \
		+ Vector3.UP * 3.0
	target.take_hit(result)


func _drop() -> void:
	_flying = false
	_velocity = Vector3.ZERO
	global_position.y = maxf(global_position.y, 0.35)
	_body_shape.set_deferred("disabled", false)
	landed.emit()


## Puts the object back on the floor when its carrier is defeated or respawns,
## so a heavy prop cannot be removed from the match by dying while holding it.
func release() -> void:
	if carrier == null:
		return
	carrier = null
	_drop()
