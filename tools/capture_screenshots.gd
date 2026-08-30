## Dev tool: poses four fighters in the arena and writes PNGs.
##
## Run under a virtual framebuffer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --rendering-method gl_compatibility res://tools/capture_screenshots.tscn -- <out_dir>
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

## Poses chosen to show the whole arena vocabulary at once: floor, centre
## platform, low ledge and the high ledge only a double-jumper can reach.
const POSES := [
	Vector3(-3.0, 0.3, 7.0),
	Vector3(0.0, 3.9, 0.0),
	Vector3(12.0, 2.4, 6.0),
	Vector3(-12.5, 4.5, -7.0),
]

var _main: Node3D
var _fighters: Array[Fighter] = []
var _out_dir := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]

	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false

	for i in 4:
		var slot: PlayerSlot = PlayerManager.slots[i]
		slot.source = ScriptedInputSource.new()
		PlayerManager.player_joined.emit(slot)
		await get_tree().physics_frame
		_fighters.append(slot.fighter as Fighter)

	await _pose(POSES)
	await _capture("m1_four_players.png")

	# Two fighters close together, to show the camera pushing in.
	await _pose([Vector3(-2.5, 0.3, 11.0), Vector3(2.5, 0.3, 11.0),
		Vector3(-1.0, 0.3, 13.5), Vector3(4.0, 0.3, 13.5)])
	await _capture("m1_camera_close.png")

	get_tree().quit()


func _pose(positions: Array) -> void:
	for i in _fighters.size():
		_fighters[i].global_position = positions[i]
		_fighters[i].velocity = Vector3.ZERO
	# Let gravity settle everyone onto the surface under them, and give the
	# camera time to finish its slow zoom-in before the shutter.
	for tick in 300:
		await get_tree().physics_frame
	for fighter in _fighters:
		var focus := Vector3(0.0, fighter.global_position.y, 0.0)
		if fighter.global_position.distance_to(focus) > 0.5:
			fighter.look_at(focus, Vector3.UP)


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(filename)
	var error := image.save_png(path)
	print("wrote %s (%d)" % [path, error])
