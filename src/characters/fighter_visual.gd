## The ninja model, its animation player, and its per-player recolour.
##
## Every fighter shares one mesh and one texture; the shader rotates the hue of
## the saturated crimson only, so four players read apart at a glance without
## four sets of art -- and without green faces.
class_name FighterVisual
extends Node3D

const ANIMATIONS := preload("res://assets/characters/ninja/ninja_animations.res")
const HUE_SHADER := preload("res://assets/characters/ninja/ninja_hue.gdshader")

const LIBRARY := &"ninja"
## Hue of the crimson in the source texture, measured from the atlas.
const SOURCE_HUE := 0.0
## The model stands 1.69m; the collision capsule is 1.8m.
const MODEL_SCALE := 1.065
## Seconds of cross-fade between locomotion clips.
const BLEND := 0.14
## Metres (and radians) per second the flinch eases back by.
const RECOIL_RECOVERY := 2.4

## Speed below which the fighter is standing still, in metres per second.
const IDLE_SPEED := 0.35
## Speed at which the walk gives way to the run.
const WALK_SPEED := 4.2

@onready var _model: Node3D = $Model
@onready var _player: AnimationPlayer = $Model/AnimationPlayer

var _material: ShaderMaterial
var _recoil_offset := Vector3.ZERO
var _recoil_tilt := 0.0
var _current := &""
## Set while an attack clip is playing, so locomotion does not interrupt it.
var _locked := false


func _ready() -> void:
	# The model faces +Z (its toes point that way) while Godot's forward is -Z,
	# so the scene flips it 180 degrees. Scale must not clobber that rotation.
	_model.scale = Vector3.ONE * MODEL_SCALE
	_player.add_animation_library(LIBRARY, ANIMATIONS)
	_build_material()


## Swaps the imported material for the hue shader, reusing its albedo texture.
func _build_material() -> void:
	var mesh_instance := _model.find_child("char1", true, false) as MeshInstance3D
	if mesh_instance == null:
		return

	var source := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
	_material = ShaderMaterial.new()
	_material.shader = HUE_SHADER
	if source != null and source.albedo_texture != null:
		_material.set_shader_parameter("albedo_texture", source.albedo_texture)
	mesh_instance.material_override = _material


func set_player_colour(colour: Color) -> void:
	if _material == null:
		return
	# Rotate the crimson onto the slot's hue; wrapping keeps the shortest way round.
	_material.set_shader_parameter("hue_shift", wrapf(colour.h - SOURCE_HUE, -0.5, 0.5))


func set_hit_flash(amount: float) -> void:
	if _material != null:
		_material.set_shader_parameter("hit_flash", clampf(amount, 0.0, 1.0))


## Picks a locomotion clip from how fast the fighter is actually moving, and
## scales playback to the speed so the feet do not skate.
func play_locomotion(planar_speed: float, airborne: bool) -> void:
	if _locked:
		return

	var clip := &"walk"
	var rate := 1.0
	if airborne:
		clip = &"run"
		rate = 0.7
	elif planar_speed < IDLE_SPEED:
		clip = &"walk"
		rate = 0.35
	elif planar_speed < WALK_SPEED:
		clip = &"walk"
		rate = clampf(planar_speed / 1.6, 0.5, 1.6)
	else:
		clip = &"run"
		rate = clampf(planar_speed / 5.2, 0.7, 1.7)

	_play(clip, rate)


## Plays an attack clip so that its moment of contact lands on the active
## frames. Startup and the rest are scaled independently, because frame data
## and the animation rarely divide the move the same way.
func play_attack(clip: StringName, from: float, impact: float, to: float,
		startup_seconds: float, remainder_seconds: float) -> void:
	var animation := _player.get_animation("%s/%s" % [LIBRARY, clip])
	if animation == null:
		return

	_locked = true
	_current = clip
	_player.play("%s/%s" % [LIBRARY, clip], 0.06)
	_player.seek(from, true)

	var wind_up := maxf(impact - from, 0.01)
	_player.speed_scale = wind_up / maxf(startup_seconds, 0.016)

	# Hand the rest of the clip its own rate once contact has passed.
	var follow_through := maxf(to - impact, 0.01)
	var timer := get_tree().create_timer(startup_seconds, false, true)
	timer.timeout.connect(func() -> void:
		if _locked and _current == clip:
			_player.speed_scale = follow_through / maxf(remainder_seconds, 0.016))


## Knocks the model back and tips it away from the blow, easing home over the
## next few ticks. With no hit-reaction clip yet, this is what makes a hit read
## as landing on somebody rather than just moving them.
func recoil(direction: Vector3, strength: float) -> void:
	var local := global_transform.basis.inverse() * direction
	_recoil_offset = Vector3(local.x, 0.0, local.z).normalized() * clampf(strength, 0.0, 1.0) * 0.32
	_recoil_tilt = clampf(strength, 0.0, 1.0) * 0.42


func _process(delta: float) -> void:
	if _recoil_offset == Vector3.ZERO and is_zero_approx(_recoil_tilt):
		return
	_recoil_offset = _recoil_offset.move_toward(Vector3.ZERO, RECOIL_RECOVERY * delta)
	_recoil_tilt = move_toward(_recoil_tilt, 0.0, RECOIL_RECOVERY * delta)
	_model.position = _recoil_offset
	_model.rotation.x = -_recoil_tilt


## Freezes on the current pose. Used for reactions until there are clips for
## them -- a stopped animation reads as "stunned" better than a walk cycle does.
func hold() -> void:
	_locked = true
	_player.speed_scale = 0.0


func release_attack() -> void:
	_locked = false
	_current = &""
	_player.speed_scale = 1.0


## One-shot clips for reactions, which do not need contact alignment.
func play_reaction(clip: StringName, rate := 1.0, seek_to := 0.0) -> void:
	_locked = true
	_current = clip
	_player.play("%s/%s" % [LIBRARY, clip], 0.08)
	_player.seek(seek_to, true)
	_player.speed_scale = rate


func _play(clip: StringName, rate: float) -> void:
	if _current != clip:
		_current = clip
		_player.play("%s/%s" % [LIBRARY, clip], BLEND)
	_player.speed_scale = rate
