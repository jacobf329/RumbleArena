## Owns the four player seats, device assignment, and input polling.
##
## Autoloaded, so it sits first in the scene tree and its _physics_process runs
## before any fighter's. Polling happens on the physics tick rather than the
## render frame: just-pressed edges are only meaningful if they are produced at
## the same rate the fighters consume them, otherwise a press landing between
## two physics ticks would be silently dropped.
extends Node

const MAX_PLAYERS := 4

## Slot colours double as the fighter's body colour, so "who am I" is answered
## by silhouette colour rather than by reading a HUD -- pillar P3.
const SLOT_COLORS: Array[Color] = [
	Color("e8443a"),  # red
	Color("3a8ee8"),  # blue
	Color("46c46b"),  # green
	Color("e0b53a"),  # amber
]

## Skill handed to each bot as they are added, so a bench of three is a ladder
## rather than three copies of the same opponent.
const BOT_SKILL_LADDER: Array[float] = [0.55, 0.35, 0.75, 0.45]

signal player_joined(slot: PlayerSlot)
signal player_left(slot: PlayerSlot)
signal player_device_lost(slot: PlayerSlot)
signal player_device_restored(slot: PlayerSlot)

var slots: Array[PlayerSlot] = []
## While true, an unassigned device can claim a free seat by pressing join.
var join_enabled := true

var _was_awaiting: Array[bool] = []


func _ready() -> void:
	process_priority = -100
	for i in MAX_PLAYERS:
		slots.append(PlayerSlot.new(i, SLOT_COLORS[i]))
		_was_awaiting.append(false)


func _physics_process(_delta: float) -> void:
	for slot in slots:
		if slot.source != null:
			slot.source.poll()
	_detect_reconnects()
	if join_enabled:
		_check_for_joins()


## Emits on the transition in each direction so the HUD can raise and drop a
## "reconnect controller" prompt without polling every frame.
func _detect_reconnects() -> void:
	for slot in slots:
		var awaiting := slot.is_awaiting_reconnect()
		if awaiting == _was_awaiting[slot.index]:
			continue
		_was_awaiting[slot.index] = awaiting
		if awaiting:
			player_device_lost.emit(slot)
		else:
			player_device_restored.emit(slot)


func _check_for_joins() -> void:
	if get_free_slot() == null:
		return
	for device_id in Input.get_connected_joypads():
		if not _is_device_taken(device_id) and GamepadInputSource.is_join_requested(device_id):
			_assign(GamepadInputSource.new(device_id))
			return  # one join per tick, so one press never fills two seats
	if not _is_device_taken(InputSource.KEYBOARD_DEVICE) and KeyboardInputSource.is_join_requested():
		_assign(KeyboardInputSource.new())


func _assign(source: InputSource) -> void:
	var slot := get_free_slot()
	if slot == null:
		return
	slot.source = source
	player_joined.emit(slot)


## Seats a bot. A bot is an InputSource like any other, so nothing downstream --
## the fighter, the camera, the match, the HUD -- has a branch for it: it joins
## through the same path a human does and plays through the same buttons.
func add_bot(skill := -1.0) -> PlayerSlot:
	var slot := get_free_slot()
	if slot == null:
		return null
	var chosen := skill if skill >= 0.0 else BOT_SKILL_LADDER[get_bot_count() % BOT_SKILL_LADDER.size()]
	var bot := BotInputSource.new(slot.index, chosen)
	slot.source = bot
	# Ready on arrival: a bot has no way to press the lock-in button, and a seat
	# that never readies would stall every countdown.
	slot.is_ready = true
	player_joined.emit(slot)
	return slot


## Frees the most recently seated bot. Humans are never removed this way --
## somebody who sat down keeps their seat until they unplug.
func remove_bot() -> PlayerSlot:
	for i in range(slots.size() - 1, -1, -1):
		var slot := slots[i]
		if slot.is_bot():
			slot.source = null
			slot.is_ready = false
			_was_awaiting[slot.index] = false
			player_left.emit(slot)
			return slot
	return null


## Empties the whole bench at once. The pad has exactly one spare button, so on
## a controller adding cycles round to clearing rather than needing a second.
func clear_bots() -> int:
	var removed := 0
	while remove_bot() != null:
		removed += 1
	return removed


## Empties every seat, humans included. Leaving character select is the one
## place this is right: coming back to a lobby holding the last group's picks,
## on devices nobody is still holding, is worse than starting clean.
func clear_seats() -> void:
	for slot in slots:
		if not slot.is_active():
			continue
		slot.source = null
		slot.is_ready = false
		slot.character_index = slot.index
		_was_awaiting[slot.index] = false
		player_left.emit(slot)


func get_bot_count() -> int:
	return slots.filter(func(slot: PlayerSlot) -> bool: return slot.is_bot()).size()


func get_bot_sources() -> Array[BotInputSource]:
	var bots: Array[BotInputSource] = []
	for slot in slots:
		if slot.is_bot():
			bots.append(slot.source as BotInputSource)
	return bots


func _is_device_taken(device_id: int) -> bool:
	for slot in slots:
		if slot.source != null and slot.source.owns_device(device_id):
			return true
	return false


func get_free_slot() -> PlayerSlot:
	for slot in slots:
		if not slot.is_active():
			return slot
	return null


func get_active_slots() -> Array[PlayerSlot]:
	return slots.filter(func(slot: PlayerSlot) -> bool: return slot.is_active())


func get_active_count() -> int:
	return get_active_slots().size()
