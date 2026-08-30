## An InputSource driven by a test instead of by hardware.
##
## Because fighters only ever read an InputFrame, the whole movement system is
## testable headlessly without faking device state -- which is the practical
## payoff of the "never poll Input directly" rule in GAME_DESIGN.md section 8.
class_name ScriptedInputSource
extends InputSource

var move := Vector2.ZERO
var held: Dictionary = {}


func hold(action: InputFrame.Action, down := true) -> void:
	held[action] = down


func release_all() -> void:
	held.clear()


func _read(f: InputFrame) -> void:
	f.move = move
	f.aim = move
	for action: InputFrame.Action in held:
		f.set_action(action, held[action])


func get_display_name() -> String:
	return "Scripted"


func get_device_id() -> int:
	return -100
