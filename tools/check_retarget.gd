## Answers "will these animations work on that model?"
##
##   godot --headless --path . --script res://tools/check_retarget.gd
##   ...                                                    -- res://path/to/any.glb
##
## With no argument it checks the packs the project ships, and runs as part of
## ./run_tests.sh. With a model path it checks that model against every pack, so
## a model from anywhere can be tested before any of it is wired up.
##
## The check is not "does the clip load". A clip whose track paths do not resolve
## loads fine, plays fine, and moves nothing -- one sat in this project's library
## for weeks doing exactly that. So the first thing measured is whether the
## skeleton actually moved.
##
## The second is how close two rigs end up when both play the same clip. Bone
## names are what decides whether a clip transfers at all; the rest-pose
## difference, which looks like it should matter and does not, is reported next
## to the number that does. See src/characters/animation_retarget.gd.
extends SceneTree

const MODELS := {
	"ninja": "res://assets/characters/ninja/ninja_model.glb",
	"armored_ninja": "res://assets/characters/armored_ninja/armored_ninja.glb",
}
const LIBRARIES := {
	"ninja": "res://assets/characters/ninja/ninja_animations.res",
	"armored_ninja": "res://assets/characters/armored_ninja/armored_ninja_animations.res",
}
## Summed bone travel, in the skeleton's own units, below which a clip is not
## animating anything. Not metres: these rigs are authored at roughly 100 units
## to the metre and this is a sum over 24 bones.
const MOVED := 0.05
## Average degrees of bone-direction disagreement above which two rigs are
## different enough shapes that a shared clip will read differently on them. Not
## a failure -- a stocky body and a lanky one cannot hold identical poses -- but
## worth knowing before sharing a whole library.
const POSE_TOLERANCE := 20.0

var _failures := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		_check_shipped_packs()
	else:
		_check_foreign_model(args[0])
	quit(0 if _failures == 0 else 1)


# --- The packs in the project ---

func _check_shipped_packs() -> void:
	for model_name: String in MODELS:
		var skeleton := AnimationRetarget.open(MODELS[model_name])
		if skeleton == null:
			_failures += 1
			continue
		print("\n== model %s  (%d bones, %.2fm tall)"
			% [model_name, skeleton.get_bone_count(), _height(skeleton)])
		for library_name: String in LIBRARIES:
			_report_resolution(skeleton, library_name, load(LIBRARIES[library_name]))
		AnimationRetarget.close(skeleton)

	var names := MODELS.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			_report_compatibility(names[i], MODELS[names[i]], names[j], MODELS[names[j]])

	print("\n%s" % ("every library resolves against every model" if _failures == 0
		else "FAILED: %d clip/model combinations animate nothing" % _failures))


# --- Any other model ---

func _check_foreign_model(model_path: String) -> void:
	var skeleton := AnimationRetarget.open(model_path)
	if skeleton == null:
		print("FAILED: %s has no Skeleton3D -- it is not a rigged model" % model_path)
		_failures += 1
		return
	print("== %s\n   %d bones, %.2fm tall"
		% [model_path.get_file(), skeleton.get_bone_count(), _height(skeleton)])

	for pack: String in MODELS:
		print("\n-- against the %s pack" % pack)
		var theirs := AnimationRetarget.open(MODELS[pack])
		var verdict := AnimationRetarget.compare(theirs, skeleton)
		print("   %d of %d bones shared" % [verdict["shared"], theirs.get_bone_count()])
		if not verdict["missing"].is_empty():
			print("   missing here: %s" % ", ".join(verdict["missing"]))
			print("   VERDICT: these clips cannot be carried over as they are.")
			print("            The missing bones have no target, so a DCC retarget")
			print("            against a bone map is the only route.")
			AnimationRetarget.close(theirs)
			continue
		print("   rest poses differ by up to %.1f deg (%s), which does not matter:"
			% [verdict["worst_degrees"], verdict["worst_bone"]])
		print("   a bone track is an absolute pose and replaces rest rather than")
		print("   adding to it. What matters is how the two bodies hold it:")
		_measure(theirs, skeleton, LIBRARIES[pack])
		AnimationRetarget.close(theirs)

	AnimationRetarget.close(skeleton)


## Plays one of the pack's real clips on both rigs and reports how far apart they
## end up, so the verdict is a measurement rather than a prediction.
func _measure(from: Skeleton3D, to: Skeleton3D, library_path: String) -> void:
	var library: AnimationLibrary = load(library_path)
	var names := library.get_animation_list()
	if names.is_empty():
		return
	var clip: String = names[0]
	var animation: Animation = library.get_animation(clip)
	var apart := AnimationRetarget.pose_disagreement(from, to, animation,
		animation.length * 0.35)
	print("   playing '%s' on both: %.1f deg average bone disagreement" % [clip, apart])
	if apart <= POSE_TOLERANCE:
		print("   VERDICT: portable. Same clip, close enough to the same pose.")
	else:
		print("   VERDICT: portable, but these are different shapes -- the clip")
		print("            will read differently on this model. Worth looking at")
		print("            before committing a whole library to it.")


# --- Shared reporting ---

func _report_resolution(skeleton: Skeleton3D, library_name: String,
		library: AnimationLibrary) -> void:
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.add_animation_library(library_name, library)

	var clips := []
	for full in player.get_animation_list():
		if full.begins_with(library_name + "/"):
			clips.append(full)
	clips.sort()

	var still: Array[String] = []
	for full: String in clips:
		if _travel(player, skeleton, full) < MOVED:
			still.append(String(full).get_file())
	if still.is_empty():
		print("   %-14s %2d clips, all moving" % [library_name, clips.size()])
	else:
		print("   %-14s %2d clips, NOT MOVING: %s"
			% [library_name, clips.size(), ", ".join(still)])
		_failures += still.size()

	# Stopped before the library goes: removing one out from under a player that
	# is still playing an animation in it is a segfault.
	player.stop()
	player.remove_animation_library(library_name)
	player.queue_free()


## Whether two rigs are close enough for a clip built on one to look right on the
## other. Reported rather than failed: a mismatch is a fact about the art, and
## the builder is where the decision to share or retarget gets made.
func _report_compatibility(a_name: String, a_path: String,
		b_name: String, b_path: String) -> void:
	var a := AnimationRetarget.open(a_path)
	var b := AnimationRetarget.open(b_path)
	if a == null or b == null:
		return
	var verdict := AnimationRetarget.compare(a, b)
	print("\n== rest poses: %s vs %s" % [a_name, b_name])
	if not verdict["missing"].is_empty():
		print("   bones missing on %s: %s" % [b_name, ", ".join(verdict["missing"])])
	print("   %d bones shared, rest poses up to %.1f deg apart (%s)"
		% [verdict["shared"], verdict["worst_degrees"], verdict["worst_bone"]])
	var library: AnimationLibrary = load(LIBRARIES[a_name])
	var clip: String = library.get_animation_list()[0]
	var animation: Animation = library.get_animation(clip)
	var apart := AnimationRetarget.pose_disagreement(a, b, animation,
		animation.length * 0.35)
	print("   both playing '%s': %.1f deg average bone disagreement" % [clip, apart])
	print("   %s" % ("clips are shareable between these rigs"
		if verdict["missing"].is_empty() and apart <= POSE_TOLERANCE
		else "clips will read differently on the two rigs"))
	AnimationRetarget.close(a)
	AnimationRetarget.close(b)


## Summed distance every bone moves between the start of the clip and its middle.
func _travel(player: AnimationPlayer, skeleton: Skeleton3D, clip: String) -> float:
	var animation := player.get_animation(clip)
	player.play(clip)
	var poses := []
	for time in [0.0, animation.length * 0.5]:
		player.seek(time, true)
		player.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		var frame := []
		for bone in skeleton.get_bone_count():
			frame.append(skeleton.get_bone_global_pose(bone).origin)
		poses.append(frame)
	var total := 0.0
	for bone in skeleton.get_bone_count():
		total += (poses[0][bone] as Vector3).distance_to(poses[1][bone])
	return total


## Rest-pose bounds of the mesh in its own space. Both packs sit at the origin
## unscaled; a pack that nested its mesh under a scaled node would need the
## accumulated transform instead.
func _height(skeleton: Skeleton3D) -> float:
	var root: Node = skeleton
	while root.get_parent() != null:
		root = root.get_parent()
	var tallest := 0.0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		tallest = maxf(tallest, (node as MeshInstance3D).get_aabb().end.y)
	return tallest
