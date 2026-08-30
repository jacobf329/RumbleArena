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
	PlayerManager.join_enabled = true


func _on_player_joined(slot: PlayerSlot) -> void:
	var definition := CharacterRoster.at(slot.character_index)
	var spawn := _arena.get_spawn_point(slot.index)

	var fighter: Fighter = FIGHTER_SCENE.instantiate()
	fighter.setup(slot, definition, spawn)
	_fighter_root.add_child(fighter)

	slot.fighter = fighter
	_fighters.append(fighter)
	_camera.add_target(fighter)
	_match.register(fighter)
	_hud.fighters = _fighters
	_hud.add_meter(fighter)


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
		KEY_F5:
			_reset_positions()
		KEY_F10:
			get_tree().quit()


## Puts everyone back on their spawn marker. Useful when a playtest ends with
## all four fighters wedged in one corner and you want the camera framing reset.
func _reset_positions() -> void:
	for fighter in _fighters:
		if is_instance_valid(fighter):
			fighter.respawn()
	_camera.reset_focus()
