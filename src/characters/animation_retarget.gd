## Moving a clip from the rig it was authored on to a different one.
##
## Two separate things stop a clip animating a model it did not ship with, and
## neither of them announces itself.
##
## **The node path.** Godot resolves an animation track by its whole path, and
## every export names its own rig root -- "Armature/Skeleton3D:Hips" from one
## exporter, "target_character/Skeleton3D:Hips" from the next. Identical bone
## names, different prefix, and the clip resolves nothing: it plays perfectly
## happily and moves not one bone. `rebase_to_skeleton` cuts the prefix off, and
## FighterVisual plays clips from an AnimationPlayer parented to the Skeleton3D
## so the remaining ":Hips" resolves against the skeleton itself.
##
## **The bone names.** A rebased track addresses ":Hips", and a rig without a
## bone called Hips has nothing to put there. Names are the whole contract.
##
## What is *not* a problem, despite looking like one: the two rigs' rest poses
## differ by up to 110 degrees at the hips and thighs. A bone track stores an
## absolute local pose, which replaces rest rather than adding to it, so the pose
## carries across exactly and the rest difference never enters into it. Measured:
## a clip played on the rig it was authored on and on the other one puts the
## bones within 14.0 degrees of each other on average, the same 14.0 in both
## directions, and that residual is the two bodies being different shapes -- one
## is 1.69 m and lanky, the other 1.75 m and stocky. No rotation fix reaches it.
##
## There was a `retarget()` here that read the pose as a delta from the source
## rest and hung it on the target's. It is gone. It improved that 14.0 to 10.3
## carrying a walk one way and made it 38.2 carrying a kick the other, which is
## the signature of a transform that is wrong and occasionally flattering: a
## correct one would be symmetric. Correcting only the bone's own rest and not
## its parent's is not a retarget, and a real one would be aiming at the same
## irreducible 14.0 anyway.
##
## So: if two rigs share bone names, their clips are portable, directly. If they
## do not, no amount of arithmetic here helps and the clip needs retargeting in a
## DCC tool against a bone map.
class_name AnimationRetarget


## Rewrites every bone track to ":Bone", dropping whatever the export called its
## rig root. Returns how many tracks were rewritten.
static func rebase_to_skeleton(animation: Animation) -> int:
	var changed := 0
	for track in animation.get_track_count():
		var path := String(animation.track_get_path(track))
		var colon := path.find(":")
		if colon < 0:
			continue
		if not path.substr(0, colon).ends_with("Skeleton3D"):
			push_warning("track '%s' does not address a skeleton; left as-is" % path)
			continue
		animation.track_set_path(track, NodePath(":" + path.substr(colon + 1)))
		changed += 1
	return changed


## How compatible two rigs are, as data rather than as a verdict:
##   shared           bone names on both
##   missing          names on `a` that `b` has not got -- these cannot be moved
##   worst_degrees    largest rest-pose rotation difference on a shared bone
##   worst_bone       which one
##
## Any bone missing means the clip cannot be fully carried across. worst_degrees
## is reported because it is the first thing anyone reaches for as an
## explanation, and it is not one: it does not stop a clip transferring. Use
## `pose_disagreement` for the number that actually describes the result.
static func compare(a: Skeleton3D, b: Skeleton3D) -> Dictionary:
	var missing: Array[String] = []
	var shared := 0
	var worst := 0.0
	var worst_bone := "-"
	for bone in a.get_bone_count():
		var bone_name := a.get_bone_name(bone)
		var other := b.find_bone(bone_name)
		if other < 0:
			missing.append(bone_name)
			continue
		shared += 1
		var degrees := rad_to_deg(a.get_bone_rest(bone).basis.get_rotation_quaternion() \
			.angle_to(b.get_bone_rest(other).basis.get_rotation_quaternion()))
		if degrees > worst:
			worst = degrees
			worst_bone = bone_name
	return {
		"shared": shared, "missing": missing,
		"worst_degrees": worst, "worst_bone": worst_bone,
	}


## How far apart two rigs end up when both play the same clip: the average angle
## between corresponding bone directions, in degrees.
##
## This is the measurement behind "will these animations work on that model".
## Zero for a rig against itself. Whatever it reports for two different rigs is
## the difference in their proportions, and is as good as it gets -- the pose
## itself transfers exactly.
static func pose_disagreement(a: Skeleton3D, b: Skeleton3D,
		animation: Animation, at: float) -> float:
	var first := _bone_directions(a, animation, at)
	var second := _bone_directions(b, animation, at)
	var total := 0.0
	var counted := 0
	for i in mini(first.size(), second.size()):
		var one: Vector3 = first[i]
		var two: Vector3 = second[i]
		if one == Vector3.ZERO or two == Vector3.ZERO:
			continue
		total += rad_to_deg(one.angle_to(two))
		counted += 1
	return total / maxi(counted, 1)


## Unit vector from each bone to its parent, with the clip applied. Driven by
## hand: headless there is no process step to advance a mixer.
static func _bone_directions(skeleton: Skeleton3D, animation: Animation,
		at: float) -> Array:
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var library := AnimationLibrary.new()
	library.add_animation("clip", animation)
	player.add_animation_library("probe", library)
	player.play("probe/clip")
	player.seek(at, true)
	player.advance(0.0)
	skeleton.force_update_all_bone_transforms()

	var out := []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		if parent < 0:
			out.append(Vector3.ZERO)
			continue
		var offset := skeleton.get_bone_global_pose(bone).origin \
			- skeleton.get_bone_global_pose(parent).origin
		out.append(offset.normalized() if offset.length() > 0.0001 else Vector3.ZERO)
	player.stop()
	player.queue_free()
	return out


## Instantiates a model and hands back its skeleton, parented to a holder so the
## whole tree can be freed with close(). The skeleton sits several nodes deep;
## freeing its parent leaks the rest.
static func open(model_path: String) -> Skeleton3D:
	var packed: PackedScene = load(model_path)
	if packed == null:
		push_error("could not load %s" % model_path)
		return null
	var model := packed.instantiate()
	var holder := Node3D.new()
	holder.add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		push_error("%s has no Skeleton3D" % model_path)
		holder.free()
	return skeleton


static func close(skeleton: Skeleton3D) -> void:
	if skeleton == null:
		return
	var root: Node = skeleton
	while root.get_parent() != null:
		root = root.get_parent()
	root.free()
