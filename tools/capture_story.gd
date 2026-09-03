## Dev tool: the story screens, as they actually render.
##
## Progress is faked in memory rather than read from disk, so the chapter list
## shows all three states -- cleared, next, locked -- in one shot. It also means
## running this does not touch a real save.
extends Node

const GAME := preload("res://scenes/game.tscn")

var _out := "/tmp"
var _game: Game


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	StoryProgress.persist = false
	StoryProgress.set_for_testing(2)

	_game = GAME.instantiate()
	add_child(_game)
	await _wait(20)

	_game.go_to(Game.Screen.STORY)
	await _wait(90)
	await _shot("m7-chapters")

	# Chapter four: one opponent, three stocks, the longest briefing.
	_game.story_chapter_index = 3
	_game.story_character_index = 1
	_game.go_to(Game.Screen.BRIEFING)
	await _wait(90)
	await _shot("m7-briefing")

	# And the gauntlet, which is where a lineup has to hold three of them.
	_game.story_chapter_index = 4
	_game.go_to(Game.Screen.BRIEFING)
	await _wait(60)
	await _shot("m7-briefing-gauntlet")

	_game.story_chapter_index = 3
	_game.story_won = true
	_game.go_to(Game.Screen.OUTCOME)
	await _wait(30)
	await _shot("m7-outcome")

	get_tree().quit()


func _wait(ticks: int) -> void:
	for i in ticks:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("wrote %s" % name)
