## Headless verification of the front end: menu, character select, and the
## router that moves between them.
##
## Driven through real key events rather than by calling the screens' methods,
## because the thing worth checking is that a person holding a keyboard or a pad
## can actually get from the title to a fight -- not that a private function
## returns what it says.
extends TestHarness

const GAME := preload("res://scenes/game.tscn")

var _game: Game


func _init() -> void:
	test_name = "M6 front-end test"
	boots_arena = false


func _run() -> void:
	PlayerManager.clear_seats()
	_game = GAME.instantiate()
	add_child(_game)
	await _ticks(4)

	_section("Main menu")
	_test_it_opens_on_the_menu()
	await _test_the_cursor_walks_the_menu()
	await _test_choosing_versus_opens_select()

	_section("Character select")
	await _test_empty_seats_invite_you_in()
	await _test_a_joined_seat_shows_its_ninja()
	await _test_cycling_changes_your_ninja()
	await _test_locking_in_stops_you_cycling()
	await _test_you_can_change_your_mind()

	_section("Starting a fight")
	await _test_one_ninja_is_not_a_fight()
	await _test_everyone_ready_starts_the_match()

	_section("Leaving")
	await _test_backing_out_empties_the_seats()


# --- Main menu ---

func _test_it_opens_on_the_menu() -> void:
	_check(_game.screen == Game.Screen.MENU, "the game boots to the menu, not the arena")
	_check(_menu() != null, "the menu screen is up")


## Both modes are open now that story mode exists, so what is left to check is
## the rule rather than a particular locked item: the cursor must only ever come
## to rest on an entry that will answer, whatever the menu happens to hold.
func _test_the_cursor_walks_the_menu() -> void:
	var menu := _menu()
	_check(menu._cursor == 0, "the cursor starts on Local Versus")
	await _press_key(KEY_S)
	_check(menu._cursor == 1, "pressing down moves to Story (cursor %d)" % menu._cursor)
	_check(menu.ITEMS[1]["enabled"], "which is no longer coming soon")
	await _press_key(KEY_W)
	_check(menu._cursor == 0, "and back up again")

	for step in menu.ITEMS.size():
		menu._move(1)
		_check(menu.ITEMS[menu._cursor]["enabled"],
			"step %d lands on something that answers: %s"
				% [step + 1, menu.ITEMS[menu._cursor]["label"]])
	_check(menu._cursor == 0, "and a full lap comes back where it started")


func _test_choosing_versus_opens_select() -> void:
	await _press_key(KEY_SPACE)
	await _ticks(4)
	_check(_game.screen == Game.Screen.SELECT, "Local Versus opens character select")
	_check(_select() != null, "the select screen is up")


# --- Character select ---

func _test_empty_seats_invite_you_in() -> void:
	# Seat one is deliberately not the one checked: the device that pressed A on
	# the menu is already sitting in it by the time this screen appears, which is
	# the behaviour you want rather than a stray press leaking across a screen.
	var panel := _panel(3)
	_check(panel != null, "there is a panel for every seat")
	_check("join" in panel._status.text.to_lower(),
		"an empty seat says how to take it: '%s'" % panel._status.text.replace("\n", " "))
	_check(PlayerManager.slots[0].is_active(),
		"and whoever opened the screen is already in seat one")
	_check(not PlayerManager.slots[0].is_ready,
		"but that one press did not also lock them in")



func _test_a_joined_seat_shows_its_ninja() -> void:
	_seat(0)
	await _ticks(4)
	var panel := _panel(0)
	var definition := CharacterRoster.at(PlayerManager.slots[0].character_index)
	_check(panel._name_label.text == definition.display_name,
		"a joined seat names its ninja: '%s'" % panel._name_label.text)
	# The stat block is the reason this screen exists: a roster whose whole design
	# is "nobody is well-rounded" only reads that way if you can see the numbers
	# before you commit.
	var strength_row: Label = panel._stat_rows[Stats.Type.STRENGTH]
	_check(strength_row.text.ends_with(str(definition.stat_strength)),
		"and shows its stats: '%s'" % strength_row.text)
	_check(definition.signature.display_name in panel._powers.text,
		"and its powers: '%s'" % panel._powers.text.replace("\n", " / "))


func _test_cycling_changes_your_ninja() -> void:
	var before := PlayerManager.slots[0].character_index
	await _press_seat(0, InputFrame.Action.LAUNCHER)
	_check(PlayerManager.slots[0].character_index != before,
		"the right bumper moves to another ninja")
	await _press_seat(0, InputFrame.Action.BLOCK)
	_check(PlayerManager.slots[0].character_index == before,
		"and the left bumper comes back")


func _test_locking_in_stops_you_cycling() -> void:
	await _press_seat(0, InputFrame.Action.JUMP)
	_check(PlayerManager.slots[0].is_ready, "[A] locks the seat in")
	var locked := PlayerManager.slots[0].character_index
	await _press_seat(0, InputFrame.Action.LAUNCHER)
	_check(PlayerManager.slots[0].character_index == locked,
		"and a locked seat stops cycling")


func _test_you_can_change_your_mind() -> void:
	await _press_seat(0, InputFrame.Action.GRAB)
	_check(not PlayerManager.slots[0].is_ready, "[B] un-readies a locked seat")
	await _press_seat(0, InputFrame.Action.JUMP)
	_check(PlayerManager.slots[0].is_ready, "and you can lock in again")


# --- Starting a fight ---

func _test_one_ninja_is_not_a_fight() -> void:
	await _ticks(120)
	_check(_game.screen == Game.Screen.SELECT,
		"one ready seat does not start a match")
	_check("Two ninjas needed" in _select()._status.text,
		"and the screen says why: '%s'" % _select()._status.text)


func _test_everyone_ready_starts_the_match() -> void:
	_seat(1)
	await _ticks(4)
	_check(_game.screen == Game.Screen.SELECT, "still waiting on the second seat")
	await _press_seat(1, InputFrame.Action.JUMP)

	# A short hold rather than launching on the last press, so somebody who
	# locked in by mistake has a moment to take it back.
	await _ticks(120)
	_check(_game.screen == Game.Screen.MATCH, "two ready seats start the match")
	_check(_game.get_node_or_null("Main") != null or _arena_present(),
		"and the arena is what loaded")

	# The picks made on the select screen are what the arena spawns.
	var fighters := get_tree().get_nodes_in_group(&"fighters")
	_check(fighters.size() == 2, "both seats spawned a fighter (%d)" % fighters.size())
	for node in fighters:
		var fighter := node as Fighter
		_check(fighter.character_def == CharacterRoster.at(fighter.slot.character_index),
			"%s is the ninja that seat picked" % fighter.character_def.display_name)


# --- Leaving ---

func _test_backing_out_empties_the_seats() -> void:
	_game.go_to(Game.Screen.SELECT)
	await _ticks(4)
	_check(_game.screen == Game.Screen.SELECT,
		"coming back from a match lands on select and stays there")
	_check(PlayerManager.get_active_count() > 0, "the seats survive the trip back")
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		_check(not slot.is_ready,
			"seat %d has to lock in again rather than bouncing straight back into a fight"
				% (slot.index + 1))

	_select().back_requested.emit()
	await _ticks(4)
	_check(_game.screen == Game.Screen.MENU, "backing out returns to the menu")
	_check(PlayerManager.get_active_count() == 0,
		"and empties the seats rather than holding devices nobody is using")


# --- Helpers ---

## Found by the signal it carries rather than by node name. A screen that is
## re-entered can come back under a different name if its predecessor is still
## pending deletion, and looking it up by name then silently returns null.
func _menu() -> Node:
	return _screen_with(&"play_requested")


func _select() -> Node:
	return _screen_with(&"fight_requested")


func _screen_with(signal_name: StringName) -> Node:
	for child in _game.get_children():
		if child.has_signal(signal_name):
			return child
	return null


func _panel(index: int) -> SeatPanel:
	var screen := _select()
	if screen == null:
		return null
	return screen._panels[index]


func _arena_present() -> bool:
	for child in _game.get_children():
		if child.get_node_or_null("Arena") != null:
			return true
	return false


## Takes a seat with a scripted source, the way a person pressing A would.
func _seat(index: int) -> void:
	var slot: PlayerSlot = PlayerManager.slots[index]
	slot.source = ScriptedInputSource.new()
	PlayerManager.player_joined.emit(slot)


## Named apart from the harness's own _press, which takes a source rather than a
## seat index: an override with a different signature is a parse error, and a
## parse error in a test hangs the run instead of failing it.
func _press_seat(index: int, action: InputFrame.Action) -> void:
	var source := PlayerManager.slots[index].source as ScriptedInputSource
	source.hold(action, true)
	await get_tree().process_frame
	await get_tree().process_frame
	source.hold(action, false)
	await _ticks(3)


## Held for long enough to actually land. A parsed key event does not show up in
## Input.is_physical_key_pressed for several physics frames with no window
## attached -- measured at five here -- so a press-and-release inside three
## frames is a key that was never down as far as anything polling can tell.
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
