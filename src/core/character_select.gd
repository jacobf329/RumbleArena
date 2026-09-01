## Choosing your ninja, in the arena, before the bell.
##
## There is no separate menu scene: players are already standing in the arena
## warming up, so they pick there. The bumpers cycle the roster and the jump
## button locks in -- the same button that got them a seat, which is the one
## they already have a finger on.
##
## Cycling is deliberately NOT on the movement stick. Warming up before the bell
## means walking around, and reading left and right off the stick meant a player
## changed ninja every time they took a step.
class_name CharacterSelect
extends Node

signal character_changed(slot: PlayerSlot)

@export var match_path: NodePath
## Off by default now that picking happens on its own screen before the arena
## ever loads. The node stays because the warm-up before the bell is still a
## legitimate place to change your mind, and because the M4 suite covers this
## path -- but nothing turns it on in the normal flow.
@export var enabled: bool = false

var _match: MatchManager


func _ready() -> void:
	_match = get_node_or_null(match_path) as MatchManager


func _physics_process(_delta: float) -> void:
	if not enabled or _match == null or _match.phase != MatchManager.Phase.WAITING:
		return
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		_poll(slot)


func _poll(slot: PlayerSlot) -> void:
	var frame := slot.get_frame()
	if frame == null:
		return

	if not slot.is_ready:
		var direction := 0
		if frame.is_just_pressed(InputFrame.Action.LAUNCHER):
			direction = 1
		elif frame.is_just_pressed(InputFrame.Action.BLOCK):
			direction = -1
		if direction != 0:
			slot.character_index = CharacterRoster.step(slot.character_index, direction)
			character_changed.emit(slot)

	if frame.is_just_pressed(InputFrame.Action.JUMP):
		slot.is_ready = not slot.is_ready
		_match.refresh_readiness()


## What this seat should be showing above its fighter right now.
func prompt_for(slot: PlayerSlot) -> String:
	# Honours `enabled` as well as the phase: a suite that has switched select
	# off should not still be told to advertise it.
	if not enabled or _match == null or _match.phase != MatchManager.Phase.WAITING:
		return ""
	if slot.is_ready:
		return "READY   [A] to change"
	return "[LB] %s [RB]   [A] ready" % CharacterRoster.at(slot.character_index).display_name
