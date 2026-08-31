## Dev tool: what the prompt above a fighter actually says, before the bell.
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _out := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false
	(main.get_node("Match") as MatchManager).auto_start = false
	(main.get_node("HUD/DebugHUD") as Control).hide()

	var slot: PlayerSlot = PlayerManager.slots[0]
	# A real pad, so the prompt has a real button to name.
	slot.source = GamepadInputSource.new(0)
	PlayerManager.player_joined.emit(slot)
	await get_tree().physics_frame
	var fighter := slot.fighter as Fighter

	var lens := Camera3D.new()
	lens.fov = 42.0
	add_child(lens)

	var pillar := main.get_node("Arena/Interactables/PillarWest") as Liftable
	var ground := pillar.global_position
	ground.y = 0.3
	fighter.global_position = ground + Vector3(0, 0, 1.15)
	fighter.snap_facing(Vector3(0, 0, -1))
	await _wait(20)
	lens.global_position = ground + Vector3(3.4, 2.4, 4.4)
	lens.look_at(ground + Vector3(0, 1.9, 0), Vector3.UP)
	lens.make_current()
	print("offered: %s" % fighter.get_node("Prompt").text.replace("\n", " / "))
	await _shot("prompt-lift")

	# Now holding it.
	pillar.use(fighter)
	fighter.carried = pillar
	await _wait(10)
	print("carrying: %s" % fighter.get_node("Prompt").text.replace("\n", " / "))
	await _shot("prompt-throw")
	get_tree().quit()


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
