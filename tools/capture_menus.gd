## Dev tool: the front end, as it actually renders.
extends Node

const GAME := preload("res://scenes/game.tscn")

var _out := "/tmp"
var _game: Game


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	_game = GAME.instantiate()
	add_child(_game)
	await _wait(20)
	await _shot("menu-main")

	# The controls page.
	var menu := _game.get_child(_game.get_child_count() - 1)
	menu.get_node("Controls").show()
	await _wait(4)
	await _shot("menu-controls")
	menu.get_node("Controls").hide()

	# Character select, with a mix of joined, browsing and locked-in seats.
	_game.go_to(Game.Screen.SELECT)
	await _wait(6)
	PlayerManager.slots[0].source = ScriptedInputSource.new()
	PlayerManager.player_joined.emit(PlayerManager.slots[0])
	PlayerManager.slots[0].is_ready = true
	PlayerManager.slots[1].source = ScriptedInputSource.new()
	PlayerManager.player_joined.emit(PlayerManager.slots[1])
	PlayerManager.add_bot()
	await _wait(90)
	await _shot("menu-select")
	get_tree().quit()


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("wrote %s" % name)
