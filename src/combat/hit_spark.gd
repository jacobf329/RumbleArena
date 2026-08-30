## A short-lived flash at the point of contact.
##
## Built in code rather than authored as a scene: with placeholder art, impact
## has to come from motion and timing, and those are easier to tune as numbers.
class_name HitSpark
extends Node3D

const LIFETIME := 0.22

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _age := 0.0
var _peak_scale := 1.0


static func spawn(parent: Node, at: Vector3, color: Color, strength: float) -> HitSpark:
	var spark := HitSpark.new()
	spark._peak_scale = clampf(0.5 + strength * 0.05, 0.5, 2.2)
	parent.add_child(spark)
	spark.global_position = at
	spark._tint(color)
	return spark


func _ready() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_material.albedo_color = Color.WHITE

	_mesh = MeshInstance3D.new()
	_mesh.mesh = sphere
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	scale = Vector3.ONE * 0.01


func _tint(color: Color) -> void:
	if _material != null:
		_material.albedo_color = color


func _process(delta: float) -> void:
	_age += delta
	var t := _age / LIFETIME
	if t >= 1.0:
		queue_free()
		return
	# Snap out fast, fade slow: the eye reads the sudden appearance as the hit.
	var grow := 1.0 - pow(1.0 - t, 3.0)
	scale = Vector3.ONE * (_peak_scale * (0.35 + 0.65 * grow))
	_material.albedo_color.a = 1.0 - t
