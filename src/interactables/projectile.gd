## A small flying thing that hurts whoever it reaches first.
##
## Built in code rather than authored as a scene: turrets are the only source so
## far, and a projectile is easier to tune as numbers than as a node tree.
class_name Projectile
extends Node3D

const RADIUS := 0.22
const LIFETIME := 2.5

var velocity := Vector3.ZERO
var damage := 8.0
## Never hits whoever fired it, so a hacked turret cannot kill its own owner.
var shooter: Node3D = null

var _age := 0.0
var _mesh: MeshInstance3D


static func spawn(parent: Node, at: Vector3, direction: Vector3, speed: float,
		hit_damage: float, fired_by: Node3D, colour: Color) -> Projectile:
	var projectile := Projectile.new()
	projectile.velocity = direction.normalized() * speed
	projectile.damage = hit_damage
	projectile.shooter = fired_by
	parent.add_child(projectile)
	projectile.global_position = at
	projectile._tint(colour)
	return projectile


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = RADIUS
	sphere.height = RADIUS * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


func _tint(colour: Color) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = colour
	material.emission_enabled = true
	material.emission = colour
	if _mesh == null:
		await ready
	_mesh.material_override = material


func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= LIFETIME:
		queue_free()
		return

	global_position += velocity * delta

	var shape := SphereShape3D.new()
	shape.radius = RADIUS + 0.25
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Layers.HURTBOX
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.transform = Transform3D(Basis.IDENTITY, global_position)

	for contact in get_world_3d().direct_space_state.intersect_shape(query, 4):
		var hurtbox := contact["collider"] as Hurtbox
		if hurtbox == null or hurtbox.fighter == null or hurtbox.fighter == shooter:
			continue
		_strike(hurtbox.fighter)
		queue_free()
		return

	if global_position.y < 0.1:
		queue_free()


func _strike(target: Node3D) -> void:
	var result := HitResult.new()
	result.attacker = shooter
	result.damage = damage
	result.hitstun_ticks = 16
	result.hitstop_ticks = 4
	result.position = global_position
	result.knockback = velocity.normalized() * 5.0 + Vector3.UP * 2.0
	target.take_hit(result)
