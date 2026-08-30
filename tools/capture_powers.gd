## Dev tool: poses the two new kits and writes PNGs.
##
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --rendering-method gl_compatibility res://tools/capture_powers.tscn -- <out_dir>
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _out := "/tmp"
var _fighters: Array[Fighter] = []
## Its own camera, made current: the shared arena camera frames all four
## fighters, which is right for playing and useless for looking at a shader.
var _lens: Camera3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false
	(main.get_node("Match") as MatchManager).auto_start = false
	(main.get_node("CharacterSelect") as CharacterSelect).enabled = false

	_lens = Camera3D.new()
	_lens.fov = 50.0
	add_child(_lens)

	for i in 4:
		var slot: PlayerSlot = PlayerManager.slots[i]
		slot.source = ScriptedInputSource.new()
		PlayerManager.player_joined.emit(slot)
		await get_tree().physics_frame
		_fighters.append(slot.fighter as Fighter)

	var jinsoku := _fighters[2]
	var yamabuki := _fighters[3]
	for f in _fighters:
		f.power = f.max_power

	# 1. Jinsoku's afterimage, standing where she was. Open floor west of the
	# centre platform, clear of the ramps.
	_fighters[0].global_position = Vector3(-13.0, 0.3, 13.0)
	_fighters[1].global_position = Vector3(-13.0, 0.3, 10.0)
	yamabuki.global_position = Vector3(6.0, 0.3, 9.0)
	yamabuki.snap_facing(Vector3(0, 0, -1))
	jinsoku.global_position = Vector3(-7.0, 0.3, 13.0)
	jinsoku.snap_facing(Vector3(1, 0, 0))
	await _wait(20)
	(jinsoku.character_def.signature as Power).activate(jinsoku)
	await _wait(18)
	print("decoys: ", get_tree().get_nodes_in_group(&"afterimages").size(),
		" jinsoku at ", jinsoku.global_position)
	await _look_at_spot(Vector3(-5.0, 1.0, 13.0), Vector3(0.0, 3.0, 8.0))
	await _shot("power-afterimage")

	# 2. Yamabuki mid-grapple, on her way up to the platform.
	(yamabuki.character_def.signature as Power).activate(yamabuki)
	await _wait(14)
	await _look_at_spot(yamabuki.global_position, Vector3(7.0, 3.0, 7.0))
	await _shot("power-grapple")

	# 3. Dragnet: everyone hauled in.
	yamabuki.global_position = Vector3(0.0, 4.0, 0.0)
	_fighters[0].global_position = Vector3(6.0, 0.3, 5.0)
	_fighters[1].global_position = Vector3(-6.0, 0.3, 4.0)
	jinsoku.global_position = Vector3(1.0, 0.3, 8.0)
	await _wait(20)
	(yamabuki.character_def.ultimate as Power).activate(yamabuki)
	await _wait(16)
	await _look_at_spot(yamabuki.global_position, Vector3(6.0, 4.0, 9.0))
	await _shot("power-dragnet")
	get_tree().quit()


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


## Points the capture lens at a spot from a given offset, then shoots.
func _look_at_spot(spot: Vector3, offset: Vector3) -> void:
	_lens.global_position = spot + offset
	_lens.look_at(spot, Vector3.UP)
	_lens.make_current()
	await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("wrote %s/%s.png" % [_out, name])
