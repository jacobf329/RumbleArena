## The shape of a session: menu, then character select, then a match.
##
## Until now the game booted straight into the arena, which is why joining,
## picking a ninja and starting a fight all had to happen inside it. Those are
## three different jobs and the arena is the wrong place for two of them: a
## select prompt floating over a fighter's head is a compromise you make when
## there is nowhere else to put it.
##
## The router owns exactly one screen at a time and knows nothing about what any
## of them do. Screens ask to move on by signal, which is what let story mode go
## in as three scenes and a handful of cases here rather than as a change to any
## screen that already worked.
class_name Game
extends Node

enum Screen {
	MENU,
	SELECT,       ## Versus lobby.
	MATCH,        ## Versus fight.
	STORY,        ## Chapter select.
	BRIEFING,     ## The words before a story fight.
	STORY_MATCH,  ## The same arena, seated from a chapter.
	OUTCOME,      ## What happened, and what to do next.
}

const MAIN_MENU := preload("res://scenes/ui/main_menu.tscn")
const CHARACTER_SELECT := preload("res://scenes/ui/character_select_screen.tscn")
const ARENA := preload("res://scenes/main.tscn")
const STORY_SELECT := preload("res://scenes/ui/story_screen.tscn")
const BRIEFING := preload("res://scenes/ui/briefing_screen.tscn")
const OUTCOME := preload("res://scenes/ui/outcome_screen.tscn")

## Seconds the victory banner holds before the roster comes back.
const VICTORY_LINGER := 5.0
## Shorter in story mode: the outcome screen carries the same news with the
## chapter's own words attached, so the banner is a beat rather than the beat.
const STORY_VICTORY_LINGER := 3.5

var screen: Screen = Screen.MENU

## Where the campaign is up to *in this session* -- which chapter is being
## briefed or replayed. What has been cleared for good lives in StoryProgress.
var story_chapter_index := 0
var story_character_index := 0
var story_won := false

var _current: Node
var _return_timer := 0.0
var _outcome_captured := false
var _story_device := InputSource.KEYBOARD_DEVICE
var _campaign: StoryCampaign


func _ready() -> void:
	_campaign = StoryCampaign.load_default()
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
	_outcome_captured = false

	# Anywhere you can arrive with nobody playing, nobody should still be seated.
	# The versus lobby is the exception -- it is reached *from* a match and the
	# seats are the group who were just fighting.
	if next == Screen.MENU or next == Screen.STORY:
		PlayerManager.clear_seats()

	match next:
		Screen.MENU:
			_open(MAIN_MENU)
		Screen.SELECT:
			_open(CHARACTER_SELECT)
		Screen.MATCH:
			_open(ARENA)
		Screen.STORY:
			_open(STORY_SELECT)
		Screen.BRIEFING:
			_open(BRIEFING)
		Screen.STORY_MATCH:
			_seat_story_match()
			_open(ARENA)
			# The arena turns joining back on for reconnects. A chapter is a
			# designed fight, so a spare pad does not get to add a fifth opinion
			# to it.
			PlayerManager.join_enabled = false
		Screen.OUTCOME:
			_open(OUTCOME)


func _open(packed: PackedScene) -> void:
	var node := packed.instantiate()
	# Before add_child, so the screen draws itself once in _ready rather than
	# rendering empty and then again when the data turns up.
	_configure(node)
	_current = node
	add_child(node)
	_wire(node)


## Hands a screen what it needs to know. Kept here rather than in the screens so
## that a screen still has no idea what came before it or what comes next.
func _configure(node: Node) -> void:
	var story := node as StoryScreen
	if story != null:
		story.character_index = story_character_index
		return
	var briefing := node as BriefingScreen
	if briefing != null:
		briefing.chapter = current_chapter()
		briefing.chapter_number = story_chapter_index
		briefing.character_index = story_character_index
		return
	var outcome := node as OutcomeScreen
	if outcome != null:
		outcome.chapter = current_chapter()
		outcome.chapter_number = story_chapter_index
		outcome.won = story_won
		outcome.has_next = story_chapter_index + 1 < _campaign.size()


func _wire(node: Node) -> void:
	if node.has_signal(&"play_requested"):
		node.connect(&"play_requested", _on_play_requested)
	if node.has_signal(&"story_requested"):
		node.connect(&"story_requested", _on_story_requested)
	if node.has_signal(&"quit_requested"):
		node.connect(&"quit_requested", _on_quit_requested)
	if node.has_signal(&"back_requested"):
		node.connect(&"back_requested", _on_back_requested)
	if node.has_signal(&"fight_requested"):
		node.connect(&"fight_requested", _on_fight_requested)
	if node.has_signal(&"chapter_chosen"):
		node.connect(&"chapter_chosen", _on_chapter_chosen)
	if node.has_signal(&"retry_requested"):
		node.connect(&"retry_requested", _on_retry_requested)
	if node.has_signal(&"continue_requested"):
		node.connect(&"continue_requested", _on_continue_requested)
	if node.has_signal(&"menu_requested"):
		node.connect(&"menu_requested", _on_menu_requested)


func current_chapter() -> StoryChapter:
	return _campaign.at(story_chapter_index)


func _on_play_requested() -> void:
	go_to(Screen.SELECT)


func _on_story_requested() -> void:
	go_to(Screen.STORY)


## Back means "the screen before this one", which is not always the menu.
func _on_back_requested() -> void:
	match screen:
		Screen.BRIEFING, Screen.OUTCOME:
			go_to(Screen.STORY)
		Screen.STORY:
			go_to(Screen.MENU)
		_:
			go_to(Screen.MENU)


func _on_menu_requested() -> void:
	go_to(Screen.MENU)


## Both the versus lobby and a story briefing say "fight"; which fight it is
## depends on which one is asking.
func _on_fight_requested() -> void:
	if screen == Screen.BRIEFING:
		_remember_device()
		go_to(Screen.STORY_MATCH)
	else:
		go_to(Screen.MATCH)


func _on_chapter_chosen(chapter_index: int, character_index: int) -> void:
	story_chapter_index = chapter_index
	story_character_index = character_index
	_remember_device()
	go_to(Screen.BRIEFING)


func _on_retry_requested() -> void:
	go_to(Screen.STORY_MATCH)


func _on_continue_requested() -> void:
	story_chapter_index = mini(story_chapter_index + 1, maxi(_campaign.size() - 1, 0))
	go_to(Screen.BRIEFING)


func _on_quit_requested() -> void:
	get_tree().quit()


## Whoever has been driving the menus is who story mode seats. Asked of the
## screen rather than guessed, because on four pads and a keyboard the answer is
## "the one that has been answering", and only the screen knows that.
func _remember_device() -> void:
	if _current != null and _current.has_method(&"driving_device"):
		_story_device = _current.driving_device()


## Builds the fight a chapter describes: you in seat one with the ninja you
## picked, and its opponents on the bench as bots. Nothing here is a special
## kind of match -- it is the same seats, the same bots and the same arena that
## versus uses, filled in from data instead of by four people pressing buttons.
func _seat_story_match() -> void:
	var chapter := current_chapter()
	if chapter == null:
		return
	PlayerManager.clear_seats()

	var slot := PlayerManager.seat_device(_story_device)
	if slot == null:
		return
	slot.character_index = story_character_index
	slot.is_ready = true
	slot.stock_override = chapter.player_stocks

	for opponent in chapter.get_opponents():
		var bot := PlayerManager.add_bot(opponent.skill)
		if bot == null:
			break  # four seats; a chapter with more opponents than that gets the first three
		bot.character_index = CharacterRoster.index_of(opponent.character)
		bot.stock_override = opponent.stocks


func _physics_process(delta: float) -> void:
	if _current == null:
		return
	if screen != Screen.MATCH and screen != Screen.STORY_MATCH:
		return
	var manager := _current.get_node_or_null("Match") as MatchManager
	if manager == null:
		return

	# Read off the phase rather than the match_ended signal so that a match which
	# resets itself for a rematch does not strand us in the arena either.
	if manager.phase != MatchManager.Phase.VICTORY:
		_return_timer = 0.0
		_outcome_captured = false
		return

	# Captured on the frame the phase turns, not when the timer runs out: the
	# match clears its own winner seven seconds in, and a story outcome read
	# after that would report every fight as a loss.
	if not _outcome_captured:
		_outcome_captured = true
		story_won = manager.winner != null and not manager.winner.is_bot()

	_return_timer += delta
	var linger := STORY_VICTORY_LINGER if screen == Screen.STORY_MATCH else VICTORY_LINGER
	if _return_timer < linger:
		return

	if screen == Screen.STORY_MATCH:
		if story_won:
			StoryProgress.mark_cleared(story_chapter_index)
		go_to(Screen.OUTCOME)
	else:
		go_to(Screen.SELECT)
