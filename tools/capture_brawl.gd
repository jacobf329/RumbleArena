## Dev tool: lets four bots fight and writes PNGs of the result.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --rendering-method gl_compatibility res://tools/capture_brawl.tscn -- <out_dir>
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _out_dir := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]

	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false

	var manager: MatchManager = main.get_node("Match")
	manager.countdown_seconds = 0.5
	for i in 4:
		PlayerManager.add_bot()
	await get_tree().physics_frame

	for shot in 4:
		for i in 60 * 8:
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/brawl-%d.png" % [_out_dir, shot + 1])
		print("wrote %s/brawl-%d.png  phase=%s" % [_out_dir, shot + 1, manager.phase_name()])
	get_tree().quit()
