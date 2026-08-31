## Dev tool: shows the arena's props and one barrel going off.
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _out := "/tmp"
var _lens: Camera3D
var _fighters: Array[Fighter] = []


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
	(main.get_node("HUD/DebugHUD") as Control).hide()

	_lens = Camera3D.new()
	_lens.fov = 55.0
	add_child(_lens)

	for i in 4:
		var slot: PlayerSlot = PlayerManager.slots[i]
		slot.source = ScriptedInputSource.new()
		PlayerManager.player_joined.emit(slot)
		await get_tree().physics_frame
		_fighters.append(slot.fighter as Fighter)

	var props := main.get_node("Arena/Interactables")

	# 1. The whole arena, so the new props read in context.
	for i in 4:
		_fighters[i].global_position = Vector3(-6.0 + i * 4.0, 0.3, 12.0)
	await _wait(30)
	_lens.global_position = Vector3(0, 20, 26)
	_lens.look_at(Vector3(0, 1, 0), Vector3.UP)
	_lens.make_current()
	await _shot("props-arena")

	# 2. The strength ladder, side by side.
	_lens.global_position = Vector3(-6.0, 3.2, 5.0)
	_lens.look_at(Vector3(-6.0, 1.0, -1.0), Vector3.UP)
	for node in props.get_children():
		var liftable := node as Liftable
		if liftable == null:
			continue
		match liftable.mass_class:
			1: liftable.global_position = Vector3(-8.4, 0.3, -1.0)
			2: liftable.global_position = Vector3(-6.8, 0.0, -1.0)
			4: liftable.global_position = Vector3(-5.2, 0.0, -1.0)
			5: liftable.global_position = Vector3(-3.4, 0.0, -1.0)
	await _wait(6)
	await _shot("props-ladder")

	# 3. A barrel going off under three of them.
	var barrel: ExplosiveBarrel = preload("res://scenes/interactables/barrel.tscn").instantiate()
	props.add_child(barrel)
	barrel.global_position = Vector3(0, 0.4, 10.0)
	_fighters[0].global_position = Vector3(-1.3, 0.3, 10.0)
	_fighters[1].global_position = Vector3(1.3, 0.3, 10.0)
	_fighters[2].global_position = Vector3(0, 0.3, 11.4)
	_fighters[3].global_position = Vector3(0, 0.3, 8.6)
	await _wait(20)
	_lens.global_position = Vector3(0, 3.4, 17.0)
	_lens.look_at(Vector3(0, 1.2, 10.0), Vector3.UP)
	barrel.call("_detonate")
	await _wait(5)
	await _shot("props-blast")
	get_tree().quit()


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("wrote %s/%s.png" % [_out, name])
