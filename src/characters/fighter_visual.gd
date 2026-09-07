## A character's body: its model, its animation player, and its per-player
## recolour.
##
## Which body is data now (CharacterVisual), not a constant here. The model is
## built at runtime rather than instanced in the scene, because a fighter does
## not know which ninja it is until setup() runs and three different scenes --
## the fighter, the select preview, the decoy -- would otherwise each have to be
## edited to add a model.
##
## The recolour is unchanged: one mesh and one texture per pack, and the shader
## rotates the hue of the saturated source colour only, so four players read
## apart at a glance without four sets of art -- and without green faces.
class_name FighterVisual
extends Node3D

## Worn by anything that does not name a character: the arena's placeholder
## fighter, a decoy whose owner has been freed, a preview before its first
## set_character. Keeping a default here means no consumer has to handle null.
##
## Loaded on first use rather than preloaded, and that is not a style choice.
## A preload resolves while the script is being parsed, and this one reaches a
## .tres that reaches a .glb -- so on a first launch, before Godot has imported
## anything, the parser races the importer for it. Lose that race and the script
## fails to compile, its class_name never reaches the global cache, and every
## script referencing FighterVisual goes down with it: autoloads included, so the
## arena renders and nothing responds to the controller. That is the exact
## failure that shipped twice, reached by a third route.
## tools/check_preloads.py exists to stop it being reached by a fourth.
const DEFAULT_VISUAL_PATH := "res://src/characters/visuals/ninja.tres"

static var _default_visual: CharacterVisual


static func default_visual() -> CharacterVisual:
	if _default_visual == null:
		_default_visual = load(DEFAULT_VISUAL_PATH)
	return _default_visual
const HUE_SHADER := preload("res://assets/characters/ninja/ninja_hue.gdshader")
const GHOST_SHADER := preload("res://assets/characters/ninja/ninja_ghost.gdshader")

## Library key. Internal -- clips are addressed as "clips/roundhouse_kick"
## whatever pack supplied them, so a moveset never names a character's rig.
const LIBRARY := &"clips"
## Seconds of cross-fade between locomotion clips.
const BLEND := 0.14
## Metres (and radians) per second the flinch eases back by.
const RECOIL_RECOVERY := 2.4

## Speed below which the fighter is standing still, in metres per second.
const IDLE_SPEED := 0.35
## Speed at which the walk gives way to the run.
const WALK_SPEED := 4.2

## Set in the scene by the afterimage, which is the same model wearing the
## ghost shader. Keeping the switch here means a decoy is a FighterVisual like
## any other and inherits the recolour, the animation library and the scale --
## a decoy that drifted out of sync with the fighter it copies would be worse
## than no decoy at all.
@export var ghost: bool = false

## Null until _ready or set_visual resolves it to the default.
var visual: CharacterVisual

var _model: Node3D
var _player: AnimationPlayer
var _material: ShaderMaterial
var _colour := Color.WHITE
var _recoil_offset := Vector3.ZERO
var _recoil_tilt := 0.0
var _current := &""
## Set while an attack clip is playing, so locomotion does not interrupt it.
var _locked := false


func _ready() -> void:
	if visual == null:
		visual = default_visual()
	_build_model()


## Wears a different body. A no-op when it is already wearing that one, so this
## is safe to call from set_character on every respawn.
func set_visual(next: CharacterVisual) -> void:
	var chosen := next if next != null else default_visual()
	if chosen == visual and _model != null:
		return
	visual = chosen
	if is_node_ready():
		_build_model()


func _build_model() -> void:
	if _model != null:
		_model.queue_free()
		# Removed as well as freed: queue_free lands at the end of the frame, and
		# a find_child for the mesh or the player would otherwise still turn up
		# the old body's.
		remove_child(_model)
		_model = null
	_material = null
	_player = null

	if visual == null or visual.model == null:
		return

	_model = visual.model.instantiate()
	_model.name = "Model"
	add_child(_model)
	# Models are authored facing +Z (their toes point that way) while Godot's
	# forward is -Z. Rotation first, then scale -- setting scale preserves the
	# basis rotation, but not the other way round.
	_model.rotation = Vector3(0.0, PI if visual.faces_positive_z else 0.0, 0.0)
	_model.scale = Vector3.ONE * visual.model_scale

	_build_player()
	_build_material()
	# The colour was set before the body it belongs to existed whenever a seat
	# changes ninja: the panel recolours once and then swaps the model.
	set_player_colour(_colour)
	_current = &""
	_locked = false


## Plays the pack's clips from a player parented to the skeleton itself.
##
## Not the AnimationPlayer the .glb imported with: that one's root is the scene
## root, so its tracks carry whatever the export called it ("Armature/",
## "target_character/"). The library is built with those prefixes stripped -- a
## bone track is just ":Hips" -- so it has to be played from something whose
## root *is* the skeleton. Parenting the player to the Skeleton3D does that with
## no configuration, since an AnimationPlayer's root defaults to its parent.
##
## The payoff is that a library is no longer tied to the export it came from:
## Kurogane's pack has no walk cycle and borrows the other pack's, and neither
## model knows.
func _build_player() -> void:
	var skeleton := _model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	_player = AnimationPlayer.new()
	_player.name = "Clips"
	skeleton.add_child(_player)
	if visual.animations != null:
		_player.add_animation_library(LIBRARY, visual.animations)


## Swaps the imported material for the recolour shader, reusing its albedo
## texture. The mesh is found by the name the pack declares, falling back to the
## first one in the model -- a single-mesh export should not have to name it.
func _build_material() -> void:
	var mesh_instance: MeshInstance3D = null
	if visual.mesh_node != "":
		mesh_instance = _model.find_child(visual.mesh_node, true, false) as MeshInstance3D
	if mesh_instance == null:
		mesh_instance = _first_mesh(_model)
	if mesh_instance == null or mesh_instance.mesh == null:
		return

	var source := mesh_instance.mesh.surface_get_material(0) as BaseMaterial3D
	_material = ShaderMaterial.new()
	_material.shader = GHOST_SHADER if ghost else HUE_SHADER
	if source != null and source.albedo_texture != null:
		_material.set_shader_parameter("albedo_texture", source.albedo_texture)
	# A decoy is a flat silhouette, so surface detail would be wasted on it.
	if not ghost and source != null:
		_take_surface_maps(source)
	mesh_instance.material_override = _material


## Carries a pack's normal and occlusion/roughness/metallic maps over to the
## recolour shader when it has them.
##
## Without this the shader sets one flat roughness for the whole body, which is
## all the first pack could offer -- it ships an albedo map and nothing else. The
## armoured pack ships all three at 2K, and throwing away two of them to reuse a
## constant would make a plate and a cloth wrap reflect identically.
func _take_surface_maps(source: BaseMaterial3D) -> void:
	if source.normal_texture != null:
		_material.set_shader_parameter("normal_texture", source.normal_texture)
		_material.set_shader_parameter("use_normal_map", true)
		_material.set_shader_parameter("normal_strength", source.normal_scale)
	# glTF hands Godot one packed texture and points both slots at it.
	var orm := source.roughness_texture
	if orm == null:
		orm = source.metallic_texture
	if orm != null:
		_material.set_shader_parameter("orm_texture", orm)
		_material.set_shader_parameter("use_orm_map", true)


func _first_mesh(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func set_player_colour(colour: Color) -> void:
	_colour = colour
	if _material == null:
		return
	if ghost:
		# A decoy is drawn flat in the slot colour rather than hue-rotated, so it
		# takes the colour directly.
		_material.set_shader_parameter("ghost_color", colour)
		return
	# Rotate the source colour onto the slot's hue; wrapping keeps the shortest
	# way round.
	_material.set_shader_parameter("hue_shift", wrapf(colour.h - visual.source_hue, -0.5, 0.5))


## How solid the afterimage looks. No-op on a real fighter.
func set_ghost_alpha(amount: float) -> void:
	if _material != null and ghost:
		_material.set_shader_parameter("ghost_alpha", clampf(amount, 0.0, 1.0))


func set_hit_flash(amount: float) -> void:
	if _material != null:
		_material.set_shader_parameter("hit_flash", clampf(amount, 0.0, 1.0))


## Picks a locomotion clip from how fast the fighter is actually moving, and
## scales playback to the speed so the feet do not skate.
func play_locomotion(planar_speed: float, airborne: bool) -> void:
	if _locked or _player == null:
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
	if _player == null:
		return
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
	if _model == null:
		return
	_model.position = _recoil_offset
	_model.rotation.x = -_recoil_tilt


## Freezes on the current pose. Used for reactions until there are clips for
## them -- a stopped animation reads as "stunned" better than a walk cycle does.
func hold() -> void:
	_locked = true
	if _player != null:
		_player.speed_scale = 0.0


func release_attack() -> void:
	_locked = false
	_current = &""
	if _player != null:
		_player.speed_scale = 1.0


## One-shot clips for reactions, which do not need contact alignment.
func play_reaction(clip: StringName, rate := 1.0, seek_to := 0.0) -> void:
	if _player == null:
		return
	_locked = true
	_current = clip
	_player.play("%s/%s" % [LIBRARY, clip], 0.08)
	_player.seek(seek_to, true)
	_player.speed_scale = rate


func _play(clip: StringName, rate: float) -> void:
	if _player == null:
		return
	if _current != clip:
		_current = clip
		_player.play("%s/%s" % [LIBRARY, clip], BLEND)
	_player.speed_scale = rate
