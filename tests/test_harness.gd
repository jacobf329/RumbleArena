## Shared plumbing for the headless test scenes.
##
## Every test runs the real main scene with scripted input sources, so what is
## exercised is the same code path a player drives -- not a parallel test-only
## one. Subclasses override _run().
class_name TestHarness
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var test_name := "test"

var _failures: Array[String] = []
var _checks := 0
var _main: Node3D
var _camera: ArenaCamera
var match_manager: MatchManager
var character_select: CharacterSelect


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	_camera = _main.get_node("ArenaCamera")
	match_manager = _main.get_node("Match")
	# Suites that are not about match flow opt out of it; the M4 suite turns it
	# back on explicitly.
	match_manager.auto_start = false
	character_select = _main.get_node("CharacterSelect")
	character_select.enabled = false
	PlayerManager.join_enabled = false
	await _run()
	_report()


## Override with the actual checks.
func _run() -> void:
	pass


func _join(slot_index: int) -> Fighter:
	var slot: PlayerSlot = PlayerManager.slots[slot_index]
	slot.source = ScriptedInputSource.new()
	PlayerManager.player_joined.emit(slot)
	await get_tree().physics_frame
	return slot.fighter as Fighter


func _source(fighter: Fighter) -> ScriptedInputSource:
	return fighter.slot.source as ScriptedInputSource


## Holds an action for two ticks then releases, producing exactly one
## just-pressed edge that the fighter is guaranteed to observe.
func _press(source: ScriptedInputSource, action: InputFrame.Action) -> void:
	source.hold(action, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(action, false)
	await get_tree().physics_frame


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _section(title: String) -> void:
	print("")
	print("  -- %s" % title)


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		_failures.append(description)


func _report() -> void:
	print("")
	print("%s: %d checks, %d failed" % [test_name, _checks, _failures.size()])
	for failure in _failures:
		print("  failed: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
