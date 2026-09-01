## Navigation for screens where nobody has a seat yet.
##
## A menu is not a player. Before anyone has joined there is no PlayerSlot to
## read, and whoever is holding a controller should be able to drive the thing --
## so this polls every connected pad plus the keyboard and answers "did anybody
## press up", rather than asking a particular device.
##
## Built on the same GamepadInputSource the fighters use, so the pad layout is
## defined in exactly one place and a menu cannot drift out of step with the
## game. The keyboard half is read directly: arrows, Enter and Escape are menu
## keys that the in-game mapping has no reason to carry.
class_name MenuInput
extends RefCounted

enum Action { UP, DOWN, LEFT, RIGHT, CONFIRM, BACK }

## Seconds a direction is held before it starts repeating.
const REPEAT_DELAY := 0.42
## Seconds between repeats after that.
const REPEAT_RATE := 0.13
## How far the stick has to go before it counts as a direction at all.
const STICK_THRESHOLD := 0.55

var _pads: Dictionary = {}
var _held: Dictionary = {}
var _fired: Dictionary = {}
var _repeat_at: Dictionary = {}


## Polls every device. Call once per frame before asking anything.
func poll(delta: float) -> void:
	_sync_pads()
	for device: int in _pads:
		(_pads[device] as GamepadInputSource).poll()

	for action: Action in [Action.UP, Action.DOWN, Action.LEFT, Action.RIGHT,
			Action.CONFIRM, Action.BACK]:
		_update(action, _is_down(action), delta)


## True on the frame an action is first pressed, and again on each repeat while
## a direction is held. Confirm and back never repeat: holding A should not walk
## you through three menu items.
func just_pressed(action: Action) -> bool:
	return _fired.get(action, false)


func _update(action: Action, down: bool, delta: float) -> void:
	var was: bool = _held.get(action, false)
	_held[action] = down
	_fired[action] = false

	if not down:
		_repeat_at[action] = 0.0
		return

	if not was:
		_fired[action] = true
		_repeat_at[action] = REPEAT_DELAY
		return

	if action == Action.CONFIRM or action == Action.BACK:
		return

	var remaining: float = _repeat_at.get(action, REPEAT_DELAY) - delta
	if remaining <= 0.0:
		_fired[action] = true
		remaining = REPEAT_RATE
	_repeat_at[action] = remaining


func _is_down(action: Action) -> bool:
	return _keyboard_down(action) or _pad_down(action)


## Physical keys, matching KeyboardInputSource. is_key_pressed reads the
## layout-dependent keycode; the physical one is what a WASD layout actually
## means, and it is also the one that answers correctly with no window attached.
func _keyboard_down(action: Action) -> bool:
	match action:
		Action.UP:
			return Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)
		Action.DOWN:
			return Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)
		Action.LEFT:
			return Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
		Action.RIGHT:
			return Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
		Action.CONFIRM:
			return Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_ENTER)
		Action.BACK:
			return Input.is_physical_key_pressed(KEY_ESCAPE) \
				or Input.is_physical_key_pressed(KEY_BACKSPACE)
	return false


func _pad_down(action: Action) -> bool:
	for device: int in _pads:
		var frame: InputFrame = (_pads[device] as GamepadInputSource).frame
		match action:
			Action.UP:
				if frame.move.y > STICK_THRESHOLD:
					return true
			Action.DOWN:
				if frame.move.y < -STICK_THRESHOLD:
					return true
			Action.LEFT:
				if frame.move.x < -STICK_THRESHOLD:
					return true
			Action.RIGHT:
				if frame.move.x > STICK_THRESHOLD:
					return true
			Action.CONFIRM:
				if frame.is_held(InputFrame.Action.JUMP):
					return true
			Action.BACK:
				if frame.is_held(InputFrame.Action.GRAB):
					return true
	return false


## Pads come and go while a menu is open, so the set is rebuilt rather than
## captured once.
func _sync_pads() -> void:
	var connected := Input.get_connected_joypads()
	for device: int in connected:
		if not _pads.has(device):
			_pads[device] = GamepadInputSource.new(device)
	for device: int in _pads.keys():
		if not connected.has(device):
			_pads.erase(device)
