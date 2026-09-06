## Builds a pack's AnimationLibrary from its raw exports.
##
##   godot --headless --path . --script res://tools/build_animation_library.gd -- <pack>
##   ... -- all
##
## Two things happen here that make a pack's clips usable by any model.
##
## **Track paths are rewritten to be relative to the skeleton.** A clip exported
## from Meshy addresses its bones through whatever the export happened to call
## its root -- "Armature/Skeleton3D:Hips" for one pack, "target_character/
## Skeleton3D:Hips" for the next. The bone names are identical; only the prefix
## differs, and Godot resolves a track by the whole path, so a clip from one
## export silently animates nothing on the other's model. That is not a
## hypothetical: an early clip in the ninja pack sat in the library for weeks
## resolving zero of its 22 tracks. Rewriting every bone track to ":Bone" and
## playing it from an AnimationPlayer parented to the Skeleton3D removes the
## prefix from the question entirely -- after this, any pack's clips play on any
## model with the same bone names.
##
## **Horizontal root motion is flattened.** The fighter's position is owned by
## the physics body and the knockback system, so an animation that also slides
## the character would fight it. Vertical motion is kept: that is the crouch and
## the leap.
extends SceneTree

const PACKS := {
	"ninja": {
		"clips_dir": "res://assets/characters/ninja/animations",
		"output": "res://assets/characters/ninja/ninja_animations.res",
		# Same bone names as everything else, but exported with a different root.
		# It is readable again now that paths are normalised.
		"skip": [],
	},
	"armored_ninja": {
		# One .glb carrying the model and all fifteen clips, rather than a
		# directory of one-clip exports.
		"source_glb": "res://assets/characters/armored_ninja/armored_ninja.glb",
		"output": "res://assets/characters/armored_ninja/armored_ninja_animations.res",
		# The pack's own names on the left of nothing -- every clip keeps the name
		# it was generated under. These are the extra keys the movesets ask for,
		# pointing at the same Animation object rather than a copy of it.
		"alias": {
			"run": "ninja_run",
			"run_alt": "ninja_run",
			"run_fast": "ninja_run",
			"punch_combo": "punch_cross",
			"double_kick": "kick_side",
			"roundhouse_kick": "roundhouse",
			"shoulder_throw": "throw",
			"spin_jump": "crane_kick",
		},
		"model": "res://assets/characters/armored_ninja/armored_ninja.glb",
		# This pack has no walk cycle, and its run is a deep forward-leaning
		# crouch -- played slowly for standing still it left Kurogane a head
		# shorter than everyone else. So the walk is borrowed from the other
		# pack, which works because the two rigs share all 24 bone names: a bone
		# track is an absolute local pose and carries across as-is.
		"borrow": {
			"walk": {"clip": "res://assets/characters/ninja/animations/walk.glb"},
		},
	},
}

## Clips that should loop rather than play once.
const LOOPING := ["walk", "run", "run_fast", "run_alt", "ninja_run"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var wanted: Array = PACKS.keys() if args.is_empty() or args[0] == "all" else [args[0]]
	var status := 0
	for pack: String in wanted:
		if not PACKS.has(pack):
			push_error("unknown pack '%s'; known: %s" % [pack, ", ".join(PACKS.keys())])
			status = 1
			continue
		if not _build(pack):
			status = 1
	quit(status)


func _build(pack: String) -> bool:
	var spec: Dictionary = PACKS[pack]
	var library := AnimationLibrary.new()
	print("\n== %s" % pack)

	var sources: Dictionary = {}  # name -> Animation
	if spec.has("clips_dir"):
		sources = _from_directory(spec["clips_dir"], spec.get("skip", []))
	if spec.has("source_glb"):
		sources.merge(_from_glb(spec["source_glb"]))
	for key: String in spec.get("borrow", {}):
		var loan: Dictionary = spec["borrow"][key]
		var borrowed := _one_clip(loan["clip"])
		if borrowed == null:
			return false
		print("  %-20s borrowed from %s" % [key, String(loan["clip"]).get_file()])
		sources[key] = borrowed

	var keys := sources.keys()
	keys.sort()
	for key: String in keys:
		var animation: Animation = sources[key]
		_add(library, key, animation)
		print("  %-20s %5.2fs  %2d tracks" % [key, animation.length, animation.get_track_count()])

	# Aliases share the Animation object rather than duplicating it: the same
	# kick under two names is one kick.
	for alias: String in spec.get("alias", {}):
		var target: String = spec["alias"][alias]
		if not sources.has(target):
			push_error("alias %s -> %s: no such clip" % [alias, target])
			return false
		_add(library, alias, sources[target])
		print("  %-20s -> %s" % [alias, target])

	var error := ResourceSaver.save(library, spec["output"])
	print("  saved %d animations -> %s"
		% [library.get_animation_list().size(),
			"ok" if error == OK else "ERROR %d" % error])
	return error == OK


func _add(library: AnimationLibrary, key: String, animation: Animation) -> void:
	animation.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE
	library.add_animation(key, animation)


## A directory of one-clip exports: the file name is the clip name.
func _from_directory(directory: String, skip: Array) -> Dictionary:
	var out := {}
	var names := DirAccess.get_files_at(directory)
	names.sort()
	for file in names:
		if not file.ends_with(".glb"):
			continue
		var key := file.get_basename()
		if key in skip:
			print("  %-20s skipped" % key)
			continue
		var animation := _one_clip("%s/%s" % [directory, file])
		if animation != null:
			out[key] = animation
	return out


## The clip in a one-clip export -- by which is meant the longest one in it.
## Some exports carry a stub alongside the real animation (a 0.07s "clip0" sits
## in one of them), and taking whichever came first quietly picked the stub.
func _one_clip(path: String) -> Animation:
	var clips := _from_glb(path)
	if clips.is_empty():
		push_error("no animation in %s" % path)
		return null
	var best: Animation = null
	for name: String in clips:
		var candidate: Animation = clips[name]
		if best == null or candidate.length > best.length:
			best = candidate
	return best


## Every animation in one .glb, prepared and keyed by its own name.
func _from_glb(path: String) -> Dictionary:
	var out := {}
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("could not load %s" % path)
		return out
	var scene := packed.instantiate()
	var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player == null:
		push_error("no AnimationPlayer in %s" % path)
		scene.free()
		return out

	for name in player.get_animation_list():
		# Godot writes a RESET pose alongside the real clips; it is not one.
		if name == "RESET":
			continue
		var animation: Animation = player.get_animation(name).duplicate(true)
		var rebased := AnimationRetarget.rebase_to_skeleton(animation)
		_flatten_root_motion(animation)
		out[name] = animation
		if rebased == 0:
			push_warning("%s: no skeleton tracks rebased" % name)
	scene.free()
	return out


## Pins the hips' horizontal translation to its first key, leaving Y alone.
func _flatten_root_motion(animation: Animation) -> int:
	var changed := 0
	for track in animation.get_track_count():
		if animation.track_get_type(track) != Animation.TYPE_POSITION_3D:
			continue
		if not String(animation.track_get_path(track)).ends_with(":Hips"):
			continue
		var key_count := animation.track_get_key_count(track)
		if key_count == 0:
			continue
		var origin: Vector3 = animation.track_get_key_value(track, 0)
		for key in key_count:
			var value: Vector3 = animation.track_get_key_value(track, key)
			animation.track_set_key_value(track, key, Vector3(origin.x, value.y, origin.z))
			changed += 1
	return changed
