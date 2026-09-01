## The shape of a session: menu, then character select, then a match.
##
## Until now the game booted straight into the arena, which is why joining,
## picking a ninja and starting a fight all had to happen inside it. Those are
## three different jobs and the arena is the wrong place for two of them: a
## select prompt floating over a fighter's head is a compromise you make when
## there is nowhere else to put it.
##
## The router owns exactly one screen at a time and knows nothing about what any
## of them do. Screens ask to move on by signal, so a new one -- story mode --
## is a scene and a case here, not a change to any existing screen.
class_name Game
extends Node

enum Screen { MENU, SELECT, MATCH }

const MAIN_MENU := preload("res://scenes/ui/main_menu.tscn")
const CHARACTER_SELECT := preload("res://scenes/ui/character_select_screen.tscn")
const ARENA := preload("res://scenes/main.tscn")

## Seconds the victory banner holds before the roster comes back.
const VICTORY_LINGER := 5.0

var screen: Screen = Screen.MENU

var _current: Node
var _return_timer := 0.0


func _ready() -> void:
	go_to(Screen.MENU)


func go_to(next: Screen) -> void:
	if _current != null:
		_current.queue_free()
		# Removed as well as freed: queue_free lands at the end of the frame, and
		# until then the old screen is still in the tree reading the same buttons
		# as the new one -- which is how one press of A crosses two screens.
		remove_child(_current)
		_current = null

	screen = next
	_return_timer = 0.0

	match next:
		Screen.MENU:
			_open(MAIN_MENU)
		Screen.SELECT:
			_open(CHARACTER_SELECT)
		Screen.MATCH:
			_open(ARENA)


func _open(packed: PackedScene) -> void:
	_current = packed.instantiate()
	add_child(_current)

	if _current.has_signal(&"play_requested"):
		_current.connect(&"play_requested", _on_play_requested)
	if _current.has_signal(&"quit_requested"):
		_current.connect(&"quit_requested", _on_quit_requested)
	if _current.has_signal(&"back_requested"):
		_current.connect(&"back_requested", _on_back_requested)
	if _current.has_signal(&"fight_requested"):
		_current.connect(&"fight_requested", _on_fight_requested)


func _on_play_requested() -> void:
	go_to(Screen.SELECT)


func _on_back_requested() -> void:
	# Leaving select empties every seat. Coming back to a lobby that still holds
	# the last group's picks, on devices nobody is holding, is worse than
	# starting clean.
	PlayerManager.clear_seats()
	go_to(Screen.MENU)


func _on_fight_requested() -> void:
	go_to(Screen.MATCH)


func _on_quit_requested() -> void:
	get_tree().quit()


func _physics_process(delta: float) -> void:
	if screen != Screen.MATCH or _current == null:
		return
	var manager := _current.get_node_or_null("Match") as MatchManager
	if manager == null:
		return

	# Back to the roster once somebody has won and the banner has had its moment.
	# Read off the phase rather than the match_ended signal so that a match which
	# resets itself for a rematch does not strand us in the arena either.
	if manager.phase == MatchManager.Phase.VICTORY:
		_return_timer += delta
		if _return_timer >= VICTORY_LINGER:
			go_to(Screen.SELECT)
	else:
		_return_timer = 0.0
