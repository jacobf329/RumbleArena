## Finds the moment of contact in each attack clip.
##
## Frame data owns gameplay timing, so an attack animation has to be told where
## its own hit lands before playback can be scaled to put that moment on the
## active frames. Rather than eyeballing it, this samples the pose every frame
## and reports peaks in how far the hands and feet reach from the hips -- a
## punch connects at full extension.
##
##   godot --headless --path . --script res://tools/analyse_impacts.gd
extends SceneTree

##   godot --headless --path . --script res://tools/analyse_impacts.gd -- <pack>
const PACKS := {
	"ninja": {
		"model": "res://assets/characters/ninja/ninja_model.glb",
		"library": "res://assets/characters/ninja/ninja_animations.res",
	},
	"armored_ninja": {
		"model": "res://assets/characters/armored_ninja/armored_ninja.glb",
		"library": "res://assets/characters/armored_ninja/armored_ninja_animations.res",
	},
}
const STEP := 1.0 / 60.0

const STRIKERS := {
	"LeftHand": "L hand", "RightHand": "R hand",
	"LeftFoot": "L foot", "RightFoot": "R foot",
}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var pack: String = args[0] if args.size() > 0 else "ninja"
	var spec: Dictionary = PACKS[pack]
	print("== %s" % pack)

	var model: Node3D = load(spec["model"]).instantiate()
	get_root().add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	# Parented to the skeleton, matching FighterVisual: the libraries hold
	# skeleton-relative track paths and resolve against nothing else.
	var player := AnimationPlayer.new()
	skeleton.add_child(player)
	player.add_animation_library(&"clips", load(spec["library"]))
	# Headless there is no process step to drive the mixer, so it is advanced by
	# hand and the skeleton is forced to recompute before each sample.
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL

	var hips := skeleton.find_bone("Hips")
	var bones := {}
	for bone_name: String in STRIKERS:
		bones[bone_name] = skeleton.find_bone(bone_name)

	var clips: Array = args.slice(1)
	if clips.is_empty():
		clips = ["punch_combo", "roundhouse_kick", "double_kick",
			"shoulder_throw", "spin_jump"]
	for clip: String in clips:
		var animation := player.get_animation("clips/" + clip)
		print("\n== %s  (%.2fs)" % [clip, animation.length])

		# reach[striker] = per-frame distance from the hips, in bone space.
		var reach := {}
		var lift := {}
		for bone_name: String in STRIKERS:
			reach[bone_name] = PackedFloat32Array()
			lift[bone_name] = PackedFloat32Array()

		player.play("clips/" + clip)
		var time := 0.0
		while time <= animation.length:
			player.seek(time, true)
			player.advance(0.0)
			skeleton.force_update_all_bone_transforms()
			var hips_pose := skeleton.get_bone_global_pose(hips)
			for bone_name: String in STRIKERS:
				var pose := skeleton.get_bone_global_pose(bones[bone_name])
				reach[bone_name].append(hips_pose.origin.distance_to(pose.origin))
				lift[bone_name].append(pose.origin.y)
			time += STEP

		# Peaks first, then the plain argmax. The peak finder is the better
		# reading when a clip has two distinct strikes in it; on a clip that
		# holds one, its threshold reports the rest pose alongside the strike and
		# the furthest-from-rest line below is the one to trust.
		for bone_name: String in STRIKERS:
			for peak in _find_peaks(reach[bone_name]):
				print("   %-7s peak at %5.2fs  (reach %.1f)"
					% [STRIKERS[bone_name], peak.x * STEP, peak.y])
		print("   %s" % "-".repeat(52))
		for bone_name: String in STRIKERS:
			var values: PackedFloat32Array = reach[bone_name]
			var best := 0
			for i in values.size():
				if values[i] > values[best]:
					best = i
			var rest: float = values[0]
			var heights: PackedFloat32Array = lift[bone_name]
			var highest := 0
			for i in heights.size():
				if heights[i] > heights[highest]:
					highest = i
			print("   %-7s furthest at %5.2fs (%+.1f)    highest at %5.2fs (%+.1f)"
				% [STRIKERS[bone_name], best * STEP, values[best] - rest,
					highest * STEP, heights[highest] - heights[0]])
	quit()


## Local maxima that clear the clip's own average by a real margin, so idle
## limb drift does not register as a strike.
func _find_peaks(values: PackedFloat32Array) -> Array[Vector2]:
	var peaks: Array[Vector2] = []
	if values.size() < 5:
		return peaks
	var total := 0.0
	var highest := 0.0
	for v in values:
		total += v
		highest = maxf(highest, v)
	var mean := total / values.size()
	var threshold := mean + (highest - mean) * 0.72

	var i := 2
	while i < values.size() - 2:
		var v := values[i]
		if v >= threshold and v >= values[i - 1] and v >= values[i - 2] \
				and v >= values[i + 1] and v >= values[i + 2]:
			peaks.append(Vector2(i, v))
			i += 12  # one peak per strike, not one per frame of the plateau
		else:
			i += 1
	return peaks
