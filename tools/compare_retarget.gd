## Dev tool: the same clip, on the rig it was authored for and on the other one.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##     --rendering-method gl_compatibility res://tools/compare_retarget.tscn -- <out dir>
##
## The proof behind "the animations are portable". Columns 1 and 2 are one clip
## on two different bodies with nothing done to it in between; 3 and 4 are the
## same for a clip going the other way. If a clip needed conversion to cross
## rigs, this is where it would be obvious.
extends Node

const PREVIEW := preload("res://scenes/ui/character_preview.tscn")
const NINJA_MODEL := "res://assets/characters/ninja/ninja_model.glb"
const ARMORED_MODEL := "res://assets/characters/armored_ninja/armored_ninja.glb"
const ARMORED_CLIPS := "res://assets/characters/armored_ninja/armored_ninja_animations.res"
const NINJA_CLIPS := "res://assets/characters/ninja/ninja_animations.res"

var _out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.055, 0.06, 0.083)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 18)
	add_child(row)

	var armored: AnimationLibrary = load(ARMORED_CLIPS)
	var ninja: AnimationLibrary = load(NINJA_CLIPS)

	# A kick authored on the armoured rig, on both bodies.
	_column(row, "1. armoured rig\nits own roundhouse",
		_visual_for(ARMORED_MODEL, 1.0286), armored, "roundhouse", 0.77, Color("46c46b"))
	_column(row, "2. ninja rig\nthe same clip, unchanged",
		_visual_for(NINJA_MODEL, 1.065), armored, "roundhouse", 0.77, Color("e8443a"))
	# A walk authored on the ninja rig, on both bodies. This one ships:
	# Kurogane's walk is this clip.
	_column(row, "3. ninja rig\nits own walk",
		_visual_for(NINJA_MODEL, 1.065), ninja, "walk", 0.35, Color("e0b53a"))
	_column(row, "4. armoured rig\nthe same clip, unchanged",
		_visual_for(ARMORED_MODEL, 1.0286), ninja, "walk", 0.35, Color("3a8ee8"))

	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/clip-portability.png" % _out)
	print("wrote clip-portability.png")
	get_tree().quit()


## A body built at runtime, which is the whole interface a pack has: a model, a
## library, and how big it is.
func _visual_for(model_path: String, scale: float) -> CharacterVisual:
	var visual := CharacterVisual.new()
	visual.model = load(model_path)
	visual.model_scale = scale
	visual.faces_positive_z = true
	visual.mesh_node = "char1"
	return visual


func _column(row: HBoxContainer, caption: String, visual: CharacterVisual,
		library: AnimationLibrary, clip: String, at: float, colour: Color) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var preview: CharacterPreview = PREVIEW.instantiate()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.custom_minimum_size = Vector2(0, 620)
	column.add_child(preview)

	var label := Label.new()
	label.add_theme_font_size_override("font_size", 22)
	label.text = caption
	label.modulate = colour
	column.add_child(label)

	visual.animations = library
	preview._visual.set_visual(visual)
	preview._visual.set_player_colour(colour)
	var player := preview._visual._player as AnimationPlayer
	if player == null or not player.has_animation("clips/%s" % clip):
		label.text += "\n(missing '%s')" % clip
		return
	player.play("clips/%s" % clip)
	player.seek(at, true)
	player.speed_scale = 0.0
	# Held, or the preview's own idle would take the pose back on the next frame.
	preview._visual._locked = true
