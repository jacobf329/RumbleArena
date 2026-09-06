extends Node3D
## Visual actor with all custom Meshy clips. Gameplay movement remains with your controller.
var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var tails: Node3D
var head_index: int = -1
var attachment_offset := Transform3D.IDENTITY

func _ready() -> void:
	var model = preload("res://assets/ninja.glb").instantiate()
	add_child(model)
	animation_player = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	head_index = skeleton.find_bone("Head")
	tails = preload("res://assets/headband_tails.glb").instantiate()
	add_child(tails)
	var desired := global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 1.64, -0.10))
	attachment_offset = (skeleton.global_transform * skeleton.get_bone_global_rest(head_index)).affine_inverse() * desired
	for mesh in tails.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var original = mesh.get_active_material(surface) as StandardMaterial3D
			var material := ShaderMaterial.new()
			material.shader = preload("res://headband_wind.gdshader")
			if original:
				material.set_shader_parameter("albedo_map", original.albedo_texture)
				material.set_shader_parameter("normal_map", original.normal_texture)
			mesh.set_surface_override_material(surface, material)
	animation_player.get_animation("ninja_run").loop_mode = Animation.LOOP_LINEAR
	play_move("ninja_run")

func _process(_delta: float) -> void:
	if head_index >= 0:
		tails.global_transform = skeleton.global_transform * skeleton.get_bone_global_pose(head_index) * attachment_offset

func play_move(move_name: String) -> void:
	if animation_player.has_animation(move_name):
		animation_player.play(move_name, 0.12)

func get_moves() -> PackedStringArray:
	var moves := animation_player.get_animation_list()
	if moves.has("RESET"):
		moves.remove_at(moves.find("RESET"))
	return moves
