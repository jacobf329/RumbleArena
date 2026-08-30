## Keyboard driver for a single player.
##
## Reads physical keycodes rather than the InputMap so that adding a player
## never means duplicating ten actions six times over.
class_name KeyboardInputSource
extends InputSource

const BINDINGS := {
	InputFrame.Action.LIGHT: KEY_J,
	InputFrame.Action.HEAVY: KEY_K,
	InputFrame.Action.LAUNCHER: KEY_L,
	InputFrame.Action.GRAB: KEY_U,
	InputFrame.Action.BLOCK: KEY_CTRL,
	InputFrame.Action.DODGE: KEY_SHIFT,
	InputFrame.Action.JUMP: KEY_SPACE,
	InputFrame.Action.INTERACT: KEY_E,
	InputFrame.Action.SIGNATURE: KEY_Q,
	InputFrame.Action.ULTIMATE: KEY_R,
}

## Any of these joins the keyboard player at the join prompt.
const JOIN_KEYS := [KEY_SPACE, KEY_ENTER]


func _read(f: InputFrame) -> void:
	var move := Vector2(
		_axis(KEY_A, KEY_D),
		_axis(KEY_S, KEY_W)
	)
	f.move = move.limit_length(1.0)
	f.aim = f.move

	for action: InputFrame.Action in BINDINGS:
		f.set_action(action, Input.is_physical_key_pressed(BINDINGS[action]))


func _axis(negative: Key, positive: Key) -> float:
	return (1.0 if Input.is_physical_key_pressed(positive) else 0.0) \
		- (1.0 if Input.is_physical_key_pressed(negative) else 0.0)


func get_display_name() -> String:
	return "Keyboard"


func get_device_id() -> int:
	return KEYBOARD_DEVICE


static func is_join_requested() -> bool:
	for key: Key in JOIN_KEYS:
		if Input.is_physical_key_pressed(key):
			return true
	return false
