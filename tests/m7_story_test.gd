## Headless verification of story mode: the campaign data, the progress file,
## the three screens, and the fight a chapter actually builds.
##
## Driven through real key events like the front-end suite, because the thing
## worth checking is that somebody with a keyboard can get from the title to the
## end of chapter one -- and, just as much, that one held key does not carry them
## there on its own.
extends TestHarness

const GAME := preload("res://scenes/game.tscn")

var _game: Game
var _campaign: StoryCampaign


func _init() -> void:
	test_name = "M7 story test"
	boots_arena = false


func _run() -> void:
	# Never touch a real save. A suite that writes to user:// is a suite that can
	# delete somebody's campaign by being run.
	StoryProgress.persist = false
	StoryProgress.set_for_testing(0)

	_section("The campaign")
	_test_the_campaign_loads()
	_test_every_chapter_is_a_fight()

	_section("Progress")
	_test_only_the_next_chapter_is_open()

	PlayerManager.clear_seats()
	StoryProgress.set_for_testing(0)
	_game = GAME.instantiate()
	add_child(_game)
	await _ticks(4)

	_section("Getting there")
	await _test_the_menu_opens_story()
	await _test_one_press_does_not_walk_the_whole_mode()

	_section("Chapter select")
	await _test_a_locked_chapter_refuses_and_says_why()
	await _test_you_pick_your_ninja_here()
	await _test_confirming_opens_the_briefing()

	_section("The briefing")
	await _test_the_briefing_names_who_you_are_fighting()
	await _test_backing_out_returns_to_the_chapters()

	_section("The fight a chapter describes")
	await _test_a_chapter_seats_its_own_fight()
	await _test_the_chapter_decides_the_stocks()

	_section("Outcome")
	await _test_winning_clears_the_chapter()
	await _test_losing_offers_another_go()
	await _test_leaving_story_mode_empties_the_seats()


# --- The campaign ---

func _test_the_campaign_loads() -> void:
	_campaign = StoryCampaign.load_default()
	_check(_campaign != null, "the campaign resource loads")
	_check(_campaign.title != "", "it has a title: '%s'" % _campaign.title)
	_check(_campaign.size() >= 6, "and %d chapters" % _campaign.size())


## The chapters are hand-written .tres files whose opponents are sub-resources,
## which is exactly the sort of thing that loads as an empty array without
## saying so. Every field the screens read gets checked here rather than being
## discovered as a blank panel.
func _test_every_chapter_is_a_fight() -> void:
	for i in _campaign.size():
		var chapter := _campaign.at(i)
		_check(chapter != null, "chapter %d loads" % (i + 1))
		if chapter == null:
			continue
		_check(chapter.title != "", "chapter %d has a title: '%s'" % [i + 1, chapter.title])
		_check(chapter.briefing.length() > 60,
			"chapter %d has something to say (%d characters)" % [i + 1, chapter.briefing.length()])
		_check(chapter.victory != "" and chapter.defeat != "",
			"chapter %d has words for winning and for losing" % (i + 1))
		var opponents := chapter.get_opponents()
		_check(opponents.size() >= 1,
			"chapter %d has somebody in it (%d)" % [i + 1, opponents.size()])
		# Three bots plus you is the whole bench; a chapter that asked for more
		# would quietly drop one.
		_check(opponents.size() <= PlayerManager.MAX_PLAYERS - 1,
			"chapter %d fits on the bench (%d)" % [i + 1, opponents.size()])
		for opponent in opponents:
			_check(opponent.character != null,
				"%s in chapter %d is a real ninja" % [opponent.display_name(), i + 1])
			var index := CharacterRoster.index_of(opponent.character)
			_check(CharacterRoster.at(index) == opponent.character,
				"%s resolves to roster seat %d" % [opponent.display_name(), index])


# --- Progress ---

func _test_only_the_next_chapter_is_open() -> void:
	StoryProgress.set_for_testing(0)
	_check(StoryProgress.is_unlocked(0), "chapter one is open from the start")
	_check(not StoryProgress.is_unlocked(1), "chapter two is not")
	_check(not StoryProgress.is_cleared(0), "and nothing is cleared yet")

	StoryProgress.mark_cleared(0)
	_check(StoryProgress.is_cleared(0), "clearing chapter one marks it")
	_check(StoryProgress.is_unlocked(1), "and opens chapter two")

	# Replaying an early chapter after reaching a late one is not a demotion.
	StoryProgress.set_for_testing(4)
	StoryProgress.mark_cleared(0)
	_check(StoryProgress.cleared_count() == 4,
		"replaying chapter one does not close chapters two to five (%d)"
			% StoryProgress.cleared_count())
	StoryProgress.set_for_testing(0)


# --- Getting there ---

func _test_the_menu_opens_story() -> void:
	_check(_game.screen == Game.Screen.MENU, "the game boots to the menu")
	await _press_key(KEY_S)
	var menu := _menu()
	_check(menu._cursor == 1, "pressing down lands on Story (cursor %d)" % menu._cursor)
	_check(menu.ITEMS[1]["enabled"], "which is no longer coming soon")


## The bug this exists for: every story screen confirms with the same button, so
## a key still held while the next screen appears reads there as a fresh press.
## One tap of SPACE used to be worth menu, chapter, briefing and the opening
## bell -- and the player never saw two of those screens.
func _test_one_press_does_not_walk_the_whole_mode() -> void:
	await _press_key(KEY_SPACE)
	await _ticks(6)
	_check(_game.screen == Game.Screen.STORY,
		"one press of SPACE reaches chapter select and stops there (%s)"
			% Game.Screen.keys()[_game.screen])
	_check(_story() != null, "the chapter list is up")


# --- Chapter select ---

func _test_a_locked_chapter_refuses_and_says_why() -> void:
	var story := _story()
	_check(story._cursor == 0, "the list opens on the chapter you are up to")
	await _press_key(KEY_S)
	_check(story._cursor == 1, "you can move onto a locked chapter to read it")

	await _press_key(KEY_SPACE)
	await _ticks(4)
	_check(_game.screen == Game.Screen.STORY, "but confirming on it goes nowhere")
	_check("Locked" in story._status.text,
		"and says so rather than doing nothing: '%s'" % story._status.text)
	await _press_key(KEY_W)


func _test_you_pick_your_ninja_here() -> void:
	var story := _story()
	var before := story.character_index
	await _press_key(KEY_D)
	_check(story.character_index != before, "right steps to another ninja")
	_check(story._ninja_name.text == CharacterRoster.at(story.character_index).display_name,
		"and the panel follows: '%s'" % story._ninja_name.text)
	await _press_key(KEY_A)
	_check(story.character_index == before, "left comes back")


func _test_confirming_opens_the_briefing() -> void:
	await _press_key(KEY_SPACE)
	await _ticks(6)
	_check(_game.screen == Game.Screen.BRIEFING, "confirming an open chapter briefs it")
	_check(_briefing() != null, "the briefing is up")


# --- The briefing ---

func _test_the_briefing_names_who_you_are_fighting() -> void:
	var briefing := _briefing()
	var chapter := _campaign.at(0)
	_check(chapter.title in briefing._title.text,
		"the briefing names the chapter: '%s'" % briefing._title.text)
	_check(briefing._briefing.text == chapter.briefing, "and carries its words")
	_check(briefing._lineup.get_child_count() == chapter.opponent_count(),
		"one lineup entry per opponent (%d of %d)"
			% [briefing._lineup.get_child_count(), chapter.opponent_count()])
	_check(str(chapter.player_stocks) in briefing._you_stocks.text,
		"and says what you are playing with: '%s'"
			% briefing._you_stocks.text.replace("\n", " / "))


func _test_backing_out_returns_to_the_chapters() -> void:
	await _press_key(KEY_ESCAPE)
	await _ticks(6)
	_check(_game.screen == Game.Screen.STORY, "back from a briefing is the chapter list")
	await _press_key(KEY_SPACE)
	await _ticks(6)
	_check(_game.screen == Game.Screen.BRIEFING, "and you can go straight back in")


# --- The fight ---

func _test_a_chapter_seats_its_own_fight() -> void:
	await _press_key(KEY_SPACE)
	await _ticks(8)
	_check(_game.screen == Game.Screen.STORY_MATCH, "confirming the briefing starts the fight")
	_check(_arena_present(), "and the arena is what loaded")

	var chapter := _campaign.at(0)
	_check(PlayerManager.get_active_count() == chapter.opponent_count() + 1,
		"one seat for you and one per opponent (%d)" % PlayerManager.get_active_count())

	var you: PlayerSlot = PlayerManager.slots[0]
	_check(you.is_active() and not you.is_bot(), "seat one is you, not a bot")
	_check(you.character_index == _game.story_character_index,
		"and holds the ninja you picked: %s"
			% CharacterRoster.at(you.character_index).display_name)

	var opponents := chapter.get_opponents()
	for i in opponents.size():
		var seat: PlayerSlot = PlayerManager.slots[i + 1]
		_check(seat.is_bot(), "seat %d is a bot" % (i + 2))
		_check(CharacterRoster.at(seat.character_index) == opponents[i].character,
			"playing %s, as the chapter asked" % opponents[i].display_name())

	# A designed fight does not accept walk-ins -- from a pad or from the bench.
	_check(not PlayerManager.join_enabled, "a spare pad cannot join a story chapter")
	var seated := PlayerManager.get_active_count()
	var arena := _arena()
	if arena != null:
		arena._add_bot()
	_check(PlayerManager.get_active_count() == seated,
		"and [BACK] does not add a fourth opinion to it (%d seats)"
			% PlayerManager.get_active_count())


## Chapter one gives you two stocks against one. That asymmetry is the whole
## reason a seat can override the match's own number, so it is checked on the
## match rather than on the resource that asked for it.
func _test_the_chapter_decides_the_stocks() -> void:
	var chapter := _campaign.at(0)
	var manager := _match()
	_check(manager != null, "the match is running")
	if manager == null:
		return
	_check(manager.get_stocks(0) == chapter.player_stocks,
		"you have the chapter's %d stocks, not the match's %d (got %d)"
			% [chapter.player_stocks, manager.stocks_per_player, manager.get_stocks(0)])
	_check(manager.get_stocks(1) == chapter.get_opponents()[0].stocks,
		"and the opponent has theirs (%d)" % manager.get_stocks(1))
	_check(chapter.player_stocks != manager.stocks_per_player,
		"which is a different number from the versus default, or this proves nothing")


# --- Outcome ---

func _test_winning_clears_the_chapter() -> void:
	var manager := _match()
	if manager == null:
		return
	# Run the real clock rather than calling _end_match: the win is decided by
	# the leader on stocks, which is the path a timed-out chapter takes.
	manager.countdown_seconds = 0.05
	manager.match_seconds = 0.05
	manager.time_left = 0.05
	await _wait_for_screen(Game.Screen.OUTCOME, 600)

	_check(_game.screen == Game.Screen.OUTCOME,
		"the fight ends on the outcome screen (%s)" % Game.Screen.keys()[_game.screen])
	_check(_game.story_won, "and you won it, being the one still holding stocks")
	_check(StoryProgress.is_cleared(0), "clearing chapter one is remembered")
	_check(StoryProgress.is_unlocked(1), "and chapter two is now open")

	var outcome := _outcome()
	_check(outcome != null and "CLEARED" in outcome._banner.text,
		"the banner says so: '%s'" % (outcome._banner.text if outcome != null else "-"))
	_check(outcome._prose.text == _campaign.at(0).victory, "with the chapter's own words")
	_check(outcome._options[0] == &"next", "and the first thing offered is the next chapter")

	await _press_key(KEY_SPACE)
	await _ticks(8)
	_check(_game.screen == Game.Screen.BRIEFING, "taking it briefs chapter two")
	_check(_game.story_chapter_index == 1,
		"which is chapter %d" % (_game.story_chapter_index + 1))


## The loss half of the outcome screen, without losing a real fight for it: what
## is worth checking is that a loss offers another go first, and that is decided
## by two booleans.
func _test_losing_offers_another_go() -> void:
	_game.story_won = false
	_game.go_to(Game.Screen.OUTCOME)
	await _ticks(6)
	var outcome := _outcome()
	_check(outcome != null and "DEFEAT" in outcome._banner.text.to_upper(),
		"a loss says so: '%s'" % (outcome._banner.text if outcome != null else "-"))
	_check(outcome._options[0] == &"retry", "and offers another go first")
	_check(outcome._prose.text == _campaign.at(1).defeat, "with the chapter's own words")
	_check(StoryProgress.cleared_count() == 1, "losing does not clear anything")


func _test_leaving_story_mode_empties_the_seats() -> void:
	_outcome().menu_requested.emit()
	await _ticks(6)
	_check(_game.screen == Game.Screen.MENU, "you can leave from the outcome screen")
	_check(PlayerManager.get_active_count() == 0,
		"and the chapter's bots do not follow you out (%d seated)"
			% PlayerManager.get_active_count())


# --- Helpers ---

## Screens are found by the signals they carry rather than by node name: a screen
## re-entered while its predecessor is still pending deletion comes back under a
## different name, and a lookup by name then silently returns null.
func _menu() -> Node:
	return _screen_with(&"play_requested")


func _story() -> StoryScreen:
	return _screen_with(&"chapter_chosen") as StoryScreen


func _briefing() -> BriefingScreen:
	for child in _game.get_children():
		if child is BriefingScreen:
			return child
	return null


func _outcome() -> OutcomeScreen:
	return _screen_with(&"retry_requested") as OutcomeScreen


func _screen_with(signal_name: StringName) -> Node:
	for child in _game.get_children():
		if child.has_signal(signal_name):
			return child
	return null


func _match() -> MatchManager:
	for child in _game.get_children():
		var found := child.get_node_or_null("Match") as MatchManager
		if found != null:
			return found
	return null


func _arena_present() -> bool:
	return _arena() != null


func _arena() -> Node:
	for child in _game.get_children():
		if child.get_node_or_null("Arena") != null:
			return child
	return null


## Bounded rather than open-ended: a router that never arrives should fail the
## suite, not hang it.
func _wait_for_screen(target: Game.Screen, limit: int) -> void:
	for i in limit:
		if _game.screen == target:
			return
		await get_tree().physics_frame


## Held for long enough to actually land. A parsed key event does not show up in
## Input.is_physical_key_pressed for several physics frames with no window
## attached -- measured at five -- so a press and release inside three frames is
## a key that was never down as far as anything polling can tell.
const KEY_HOLD_TICKS := 12


func _press_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(KEY_HOLD_TICKS)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await _ticks(KEY_HOLD_TICKS)
