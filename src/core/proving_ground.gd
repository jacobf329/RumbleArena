## M1 test harness.
##
## Spawns a fighter for every player who joins and hands it to the shared
## camera. This milestone exists to answer two questions before any combat code
## is written: does the single shared camera hold up with four fighters, and
## does moving feel good? Everything here is scaffolding that the real match
## flow (M4) will replace.
extends Node3D

## Four contrasting stat blocks, so the movement asymmetry of pillar P1 is
## visible from the very first playtest rather than only after powers exist.
const ROSTER: Array[String] = [
	"res://src/characters/roster/kurogane.tres",
	"res://src/characters/roster/null.tres",
	"res://src/characters/roster/jinsoku.tres",
	"res://src/characters/roster/yamabuki.tres",
]

const FIGHTER_SCENE := preload("res://scenes/fighter.tscn")

@onready var _arena: Arena = $Arena
@onready var _camera: ArenaCamera = $ArenaCamera
@onready var _fighter_root: Node3D = $Fighters
@onready var _hud: Control = $HUD/DebugHUD
@onready var _match: MatchManager = $Match

var _fighters: Array[Fighter] = []


func _ready() -> void:
	_camera.bounds = _arena.camera_bounds
	_camera.reset_focus()

	_hud.bind_match(_match)

	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.join_enabled = true


func _on_player_joined(slot: PlayerSlot) -> void:
	var definition: CharacterDef = load(ROSTER[slot.index % ROSTER.size()])
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
