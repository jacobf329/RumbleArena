## M1 test harness.
##
## Spawns a fighter for every player who joins and hands it to the shared
## camera. This milestone exists to answer two questions before any combat code
## is written: does the single shared camera hold up with four fighters, and
## does moving feel good? Everything here is scaffolding that the real match
## flow (M4) will replace.
extends Node3D

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")

@onready var _arena: Arena = $Arena
@onready var _camera: ArenaCamera = $ArenaCamera
@onready var _fighter_root: Node3D = $Fighters
@onready var _hud: Control = $HUD/DebugHUD
@onready var _match: MatchManager = $Match
@onready var _select: CharacterSelect = $CharacterSelect

var _fighters: Array[Fighter] = []


func _ready() -> void:
	_camera.bounds = _arena.camera_bounds
	_camera.reset_focus()

	_hud.bind_match(_match)
	_select.character_changed.connect(_on_character_changed)

	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	PlayerManager.join_enabled = true

	# Seats filled before this scene existed. Everybody joins and picks on the
	# select screen now, so by the time the arena loads every player_joined has
	# already been emitted -- listening for it alone gave an empty arena.
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		_on_player_joined(slot)


func _on_player_joined(slot: PlayerSlot) -> void:
	var definition := CharacterRoster.at(slot.character_index)
	var spawn := _arena.get_spawn_point(slot.index)

	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.setup(slot, definition, spawn)
	_fighter_root.add_child(fighter)

	slot.fighter = fighter
	# The one line a bot seat needs beyond a human one: the AI has to be able to
	# see the body it is driving, because unlike a thumb it has no eyes.
	var bot := slot.source as BotInputSource
	if bot != null:
		bot.fighter = fighter

	_fighters.append(fighter)
	_camera.add_target(fighter)
	_match.register(fighter)
	_hud.fighters = _fighters
	_hud.add_meter(fighter)


func _on_player_left(slot: PlayerSlot) -> void:
	var fighter := slot.fighter as Fighter
	slot.fighter = null
	if not is_instance_valid(fighter):
		return
	_fighters.erase(fighter)
	_camera.remove_target(fighter)
	_match.unregister(fighter)
	_hud.remove_meter(fighter)
	_hud.fighters = _fighters
	fighter.vacate()
	fighter.queue_free()


func _on_character_changed(slot: PlayerSlot) -> void:
	var fighter := slot.fighter as Fighter
	if fighter != null:
		fighter.set_character(CharacterRoster.at(slot.character_index))


func _process(_delta: float) -> void:
	# Character select owns the prompt above each fighter until the bell.
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		var fighter := slot.fighter as Fighter
		if fighter != null:
			fighter.select_prompt = _select.prompt_for(slot)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_F2:
			_add_bot()
		KEY_F3:
			PlayerManager.remove_bot()
		KEY_F5:
			_reset_positions()
		KEY_F10:
			get_tree().quit()


## The pad is the primary interface, so the bench has to be reachable without
## reaching for a keyboard. BACK is the only face button character select has
## not already claimed, so it does both jobs: it adds a CPU, and once the arena
## is full it clears the bench, which makes 0 -> 1 -> 2 -> 3 -> 0 a round trip
## on one button rather than a dead end.
##
## (BACK is also the natural home for a pause menu. When there is one, this
## moves; START is already the join button, so it cannot go there.)
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventJoypadButton
	if button == null or not button.pressed or button.button_index != JOY_BUTTON_BACK:
		return
	if PlayerManager.get_free_slot() == null:
		PlayerManager.clear_bots()
	else:
		_add_bot()


## Bots only join between matches. Dropping one in mid-fight would hand it a
## full set of stocks against players who have already spent theirs.
func _add_bot() -> void:
	if _match.phase == MatchManager.Phase.WAITING or _match.phase == MatchManager.Phase.COUNTDOWN:
		PlayerManager.add_bot()


## Puts everyone back on their spawn marker. Useful when a playtest ends with
## all four fighters wedged in one corner and you want the camera framing reset.
func _reset_positions() -> void:
	for fighter in _fighters:
		if is_instance_valid(fighter):
			fighter.respawn()
	_camera.reset_focus()
