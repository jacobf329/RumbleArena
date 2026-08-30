## Builds the shared ninja AnimationLibrary from the stripped clip files.
##
## Each clip .glb contributes exactly one animation. Horizontal root motion is
## flattened out: the fighter's position is owned by the physics body and the
## knockback system, so an animation that also slides the character would fight
## it. Vertical motion is kept, because that is the crouch and the leap.
##
##   godot --headless --path . --script res://tools/build_animation_library.gd
extends SceneTree

const CLIP_DIR := "res://assets/characters/ninja/animations"
const OUTPUT := "res://assets/characters/ninja/ninja_animations.res"

## Clips that should loop rather than play once.
const LOOPING := ["walk", "run", "run_fast", "run_alt"]


func _init() -> void:
	var library := AnimationLibrary.new()
	var names := DirAccess.get_files_at(CLIP_DIR)
	names.sort()

	for file in names:
		if not file.ends_with(".glb"):
			continue
		var key := file.get_basename()
		var scene: Node = load("%s/%s" % [CLIP_DIR, file]).instantiate()
		var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player == null or player.get_animation_list().is_empty():
			push_error("no animation in %s" % file)
			continue

		var source := player.get_animation(player.get_animation_list()[0])
		var animation: Animation = source.duplicate(true)
		var flattened := _flatten_root_motion(animation)
		animation.loop_mode = Animation.LOOP_LINEAR if key in LOOPING else Animation.LOOP_NONE

		library.add_animation(key, animation)
		print("  %-18s %5.2fs  %2d tracks  root-motion keys flattened: %d"
			% [key, animation.length, animation.get_track_count(), flattened])
		scene.free()

	var error := ResourceSaver.save(library, OUTPUT)
	print("\nsaved %s (%d animations) -> %s" % [OUTPUT, library.get_animation_list().size(),
		"ok" if error == OK else "ERROR %d" % error])
	quit(0 if error == OK else 1)


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
