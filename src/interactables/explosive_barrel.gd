## A barrel you can pick up, and very much should not hold on to.
##
## A Liftable that goes off on impact. Nothing else in the arena punishes the
## thrower for a bad read the way this does: it is light enough that anyone can
## carry it, so the STRENGTH ladder is not the interesting question here --
## timing is. Throw it early and it is a slow projectile somebody walks around;
## throw it late and you are standing inside the blast.
##
## The fuse is what makes it a decision rather than a free grenade. Picking one
## up starts a clock, and it detonates in your hands when that runs out.
class_name ExplosiveBarrel
extends Liftable

@export var blast_radius: float = 3.6
@export var blast_damage: float = 26.0
@export var blast_knockback: float = 15.0
@export var blast_hitstun: int = 40
## Seconds from being picked up to going off on its own.
@export var fuse_seconds: float = 3.0

signal exploded(at: Vector3)

@onready var _mesh: MeshInstance3D = $Mesh

var _fuse := 0.0
var _lit := false
var _detonated := false
var _material: StandardMaterial3D


func _ready() -> void:
	super()
	display_name = "Fuel Barrel"
	# Deliberately not gated above the weakest character. The whole point of the
	# barrel is that the ninja who can lift nothing else can still lift this, and
	# is therefore holding the most dangerous object in the room.
	mass_class = 1
	required_tier = 1
	add_to_group(&"barrels")

	var source := _mesh.material_override as StandardMaterial3D
	if source != null:
		# Its own copy, so one barrel flashing does not flash all of them.
		_material = source.duplicate()
		_mesh.material_override = _material


## Lit and counting down. Anything that wants to get away from one -- an AI, a
## future warning marker -- needs to be able to ask rather than infer.
func is_lit() -> bool:
	return _lit and not _detonated


func fuse_left() -> float:
	return _fuse if _lit else fuse_seconds


func use(fighter: Node3D) -> bool:
	if not super(fighter):
		return false
	_lit = true
	_fuse = fuse_seconds
	return true


func _physics_process(delta: float) -> void:
	super(delta)
	if _detonated:
		return
	if _lit:
		_fuse -= delta
		_flash()
		if _fuse <= 0.0:
			# In your hands. That is the cost of holding it too long.
			_detonate()


## Faster and brighter as the fuse runs down, so "put this down" is legible
## across the arena rather than a number only its carrier can see.
func _flash() -> void:
	if _material == null:
		return
	var urgency := 1.0 - clampf(_fuse / maxf(fuse_seconds, 0.01), 0.0, 1.0)
	var beat := sin(Time.get_ticks_msec() * 0.001 * TAU * lerpf(2.0, 14.0, urgency))
	var glow := maxf(beat, 0.0) * lerpf(0.4, 1.0, urgency)
	_material.emission_enabled = true
	_material.emission = Color(1.0, 0.45, 0.15)
	_material.emission_energy_multiplier = glow * 3.0


## Thrown barrels go off where they land rather than bouncing to a stop.
func _drop() -> void:
	super()
	if _lit and not _detonated:
		_detonate()


## And they go off on whoever they hit, instead of dealing the ordinary
## mass-scaled thump.
func _strike(target: Node3D) -> void:
	_detonate()


func _detonate() -> void:
	if _detonated:
		return
	_detonated = true

	# Everyone in range, the thrower included: this is the one thing in the arena
	# that does not care whose it was.
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var victim := node as Fighter
		if victim == null or victim.is_eliminated or victim.is_invulnerable():
			continue
		var offset := victim.global_position - global_position
		var distance := offset.length()
		if distance > blast_radius:
			continue

		# Falls off with distance, so being at the edge of a blast is a
		# meaningfully better outcome than being on top of it.
		var falloff := 1.0 - (distance / blast_radius) * 0.6
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length_squared() < 0.01:
			flat = Vector3.FORWARD
		var direction := (flat.normalized() + Vector3.UP * 0.7).normalized()

		var result := HitResult.new()
		result.attacker = carrier
		result.damage = blast_damage * falloff
		result.knockback = direction * blast_knockback * falloff
		result.hitstun_ticks = blast_hitstun
		result.hitstop_ticks = 8
		result.position = victim.global_position + Vector3.UP
		victim.take_hit(result)

	# A burst at the barrel's own position rather than only on whoever it caught:
	# a blast that hits nobody still has to be visible, or a near miss reads as
	# the barrel having done nothing at all.
	HitSpark.spawn(get_tree().current_scene, global_position + Vector3.UP * 0.5,
		Color(1.0, 0.62, 0.22), blast_damage * 1.6)
	_shake_the_camera()
	exploded.emit(global_position)
	queue_free()


func _shake_the_camera() -> void:
	var camera := get_viewport().get_camera_3d() as ArenaCamera
	if camera != null:
		camera.add_shake(0.9)
