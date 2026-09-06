## Verifies that every pack's clips actually move every pack's model.
##
##   godot --headless --path . --script res://tools/check_retarget.gd
##
## This exists because the failure it catches is silent. Godot resolves an
## animation track by its whole node path, so a clip whose export called the rig
## root something else resolves nothing, plays perfectly happily, and moves not
## one bone. A clip in the ninja pack did exactly that for weeks. Nothing about
## the game looks broken when it happens -- the fighter simply stands still
## through its own punch.
##
## So the first check is not "does the clip load" but "did the skeleton move",
## measured as total bone travel between the pose at rest and the pose mid-clip,
## for every library against every model.
##
## That answers whether a clip *resolves*, which is not the same as whether it
## *looks right*, and the difference cost a hunched Kurogane to learn. A bone
## track stores an absolute local pose, so a clip built for one rig imposes that
## pose on another and the result differs from the original by however far the
## two rest poses differ. The two packs here share all 24 bone names and sit up
## to 110 degrees apart at the hips and thighs. Mechanically interchangeable,
## visually not. So the second check compares rest poses and says which pairs of
## rigs may actually share clips.
extends SceneTree

const MODELS := {
	"ninja": "res://assets/characters/ninja/ninja_model.glb",
	"armored_ninja": "res://assets/characters/armored_ninja/armored_ninja.glb",
}
const LIBRARIES := {
	"ninja": "res://assets/characters/ninja/ninja_animations.res",
	"armored_ninja": "res://assets/characters/armored_ninja/armored_ninja_animations.res",
}
## Metres of summed bone travel below which a clip is not animating anything.
const MOVED := 0.05
## Degrees of rest-pose difference on any bone above which two rigs cannot share
## clips without retargeting. Small differences show as a slightly-off stance;
## this is set where it stops being cosmetic.
const REST_TOLERANCE := 8.0

var _failures := 0


func _init() -> void:
	for model_name: String in MODELS:
		var model: Node3D = load(MODELS[model_name]).instantiate()
		get_root().add_child(model)
		var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
		if skeleton == null:
			print("FAIL  %s has no Skeleton3D" % model_name)
			_failures += 1
			continue

		var player := AnimationPlayer.new()
		skeleton.add_child(player)
		player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

		print("\n== model %s  (%d bones, %.2fm tall)"
			% [model_name, skeleton.get_bone_count(), _height(model)])

		for library_name: String in LIBRARIES:
			player.add_animation_library(library_name, load(LIBRARIES[library_name]))
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
			# Stopped before the library goes: removing one out from under a
			# player that is still playing an animation in it is a segfault.
			player.stop()
			player.remove_animation_library(library_name)

		model.get_parent().remove_child(model)
		model.free()

	_compare_rest_poses()

	print("\n%s" % ("every library resolves against every model" if _failures == 0
		else "FAILED: %d clip/model combinations animate nothing" % _failures))
	quit(0 if _failures == 0 else 1)


## Whether two rigs are close enough for a clip built on one to look right on the
## other. Reported rather than failed: a mismatch is a fact about the art, not a
## broken build, and the builder is where the decision to share or not is made.
func _compare_rest_poses() -> void:
	var names := MODELS.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a := _skeleton_of(MODELS[names[i]])
			var b := _skeleton_of(MODELS[names[j]])
			if a == null or b == null:
				continue
			var worst := 0.0
			var worst_bone := ""
			var missing: Array[String] = []
			for bone in a.get_bone_count():
				var bone_name := a.get_bone_name(bone)
				var other := b.find_bone(bone_name)
				if other < 0:
					missing.append(bone_name)
					continue
				var degrees := rad_to_deg(a.get_bone_rest(bone).basis.get_rotation_quaternion() \
					.angle_to(b.get_bone_rest(other).basis.get_rotation_quaternion()))
				if degrees > worst:
					worst = degrees
					worst_bone = bone_name
			print("\n== rest poses: %s vs %s" % [names[i], names[j]])
			if not missing.is_empty():
				print("   bones missing on %s: %s" % [names[j], ", ".join(missing)])
			print("   worst difference %.1f deg (%s)" % [worst, worst_bone])
			print("   %s" % ("clips can be shared between these rigs"
				if worst <= REST_TOLERANCE and missing.is_empty()
				else "clips must be retargeted, not shared: a borrowed clip will pose the other rig wrong"))


func _skeleton_of(path: String) -> Skeleton3D:
	var model: Node3D = load(path).instantiate()
	get_root().add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	return skeleton


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


## Tallest point of the mesh's AABB, so a pack can be scaled onto the capsule.
func _height(model: Node3D) -> float:
	var tallest := 0.0
	# Rest-pose bounds in the mesh's own space. Both packs sit at the origin
	# unscaled, so this is the model's height; a pack that nested its mesh under
	# a scaled node would need the accumulated transform instead.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		tallest = maxf(tallest, (node as MeshInstance3D).get_aabb().end.y)
	return tallest
