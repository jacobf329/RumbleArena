## Joining, picking a ninja, and locking in -- on a screen built for it.
##
## This used to happen in the arena, above the fighters' heads, because there was
## nowhere else to put it. That worked but cost the thing a select screen is
## actually for: seeing what you are choosing between. Six stats and two named
## powers do not fit over somebody's head, so nobody ever read them, and a roster
## whose whole design is "no well-rounded ninjas" was invisible at the one moment
## it mattered.
##
## Every seat reads its own device, so four people pick at once rather than in
## turn -- the same rule as the arena, for the same reason.
extends Control

signal fight_requested
signal back_requested

@onready var _seats: HBoxContainer = $Layout/Seats
@onready var _status: Label = $Layout/Status
@onready var _hint: Label = $Layout/Hint

var _panels: Array[SeatPanel] = []
var _menu := MenuInput.new()
var _countdown := 0.0

## Seconds between everyone being ready and the arena loading.
const LAUNCH_DELAY := 1.2


func _ready() -> void:
	for slot: PlayerSlot in PlayerManager.slots:
		var panel: SeatPanel = preload("res://scenes/ui/seat_panel.tscn").instantiate()
		_seats.add_child(panel)
		_panels.append(panel)
	PlayerManager.join_enabled = true

	# Nobody arrives here already locked in. Coming back from a match with every
	# seat still ready launched the next one on the first frame -- the screen
	# appeared and vanished, and there was no moment in which anybody could have
	# changed their ninja. Re-confirming is the whole point of returning here.
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		slot.is_ready = false
	_countdown = LAUNCH_DELAY
	_refresh()


func _exit_tree() -> void:
	# The arena does its own joining for reconnects; leaving this on would let a
	# spare pad claim a seat mid-match.
	PlayerManager.join_enabled = false


## On the physics tick, matching PlayerManager: it polls the seats' own sources
## there, and reading their just-pressed edges from a render frame would drop
## every press that landed between two of them.
func _physics_process(delta: float) -> void:
	_menu.poll(delta)

	# Backing out only while nobody has committed. Once seats are locked in, B is
	# how you change your mind about a ninja, and stealing it to leave the screen
	# would make un-readying impossible.
	if _menu.just_pressed(MenuInput.Action.BACK) and PlayerManager.get_active_count() == 0:
		back_requested.emit()
		return

	_poll_seats()
	_refresh()
	_advance_countdown(delta)


## Everyone picks at the same time, each on their own device.
func _poll_seats() -> void:
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		var frame := slot.get_frame()
		if frame == null:
			continue

		if not slot.is_ready:
			var direction := 0
			if frame.is_just_pressed(InputFrame.Action.LAUNCHER) \
					or frame.is_just_pressed(InputFrame.Action.HEAVY):
				direction = 1
			elif frame.is_just_pressed(InputFrame.Action.BLOCK) \
					or frame.is_just_pressed(InputFrame.Action.LIGHT):
				direction = -1
			if direction != 0:
				slot.character_index = CharacterRoster.step(slot.character_index, direction)

		if frame.is_just_pressed(InputFrame.Action.JUMP):
			slot.is_ready = not slot.is_ready
		elif frame.is_just_pressed(InputFrame.Action.GRAB) and slot.is_ready:
			slot.is_ready = false


func _refresh() -> void:
	for slot: PlayerSlot in PlayerManager.slots:
		var panel := _panels[slot.index]
		if slot.is_active():
			panel.show_character(slot, CharacterRoster.at(slot.character_index))
		else:
			panel.show_empty(slot)

	_status.text = _status_text()
	_hint.text = "[LB]/[RB] or left/right pick    [A] lock in    [B] change your mind" \
		+ "    [BACK] or [F2] add a CPU"


func _status_text() -> String:
	var joined := PlayerManager.get_active_count()
	if joined < MatchManager.MIN_PLAYERS:
		return "Two ninjas needed.  Press [A] on another pad, [SPACE] on the keyboard, or [F2] to add a CPU."
	if not _everyone_ready():
		return "Waiting on %d to lock in." % _not_ready_count()
	return "FIGHT in %.1f" % maxf(_countdown, 0.0)


func _everyone_ready() -> bool:
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		if not slot.is_ready:
			return false
	return PlayerManager.get_active_count() >= MatchManager.MIN_PLAYERS


func _not_ready_count() -> int:
	var waiting := 0
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		if not slot.is_ready:
			waiting += 1
	return waiting


## A short hold rather than launching on the last press, so somebody who locked
## in by mistake has a moment to take it back.
func _advance_countdown(delta: float) -> void:
	if not _everyone_ready():
		_countdown = LAUNCH_DELAY
		return
	_countdown -= delta
	if _countdown <= 0.0:
		fight_requested.emit()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F2:
			PlayerManager.add_bot()
		KEY_F3:
			PlayerManager.remove_bot()


## BACK on a pad adds a CPU here, the same as it does in the arena, so the one
## spare button means the same thing in both places.
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventJoypadButton
	if button == null or not button.pressed or button.button_index != JOY_BUTTON_BACK:
		return
	if PlayerManager.get_free_slot() == null:
		PlayerManager.clear_bots()
	else:
		PlayerManager.add_bot()
