## Gamepad driver bound to one device id.
##
## Reads the device directly instead of going through the InputMap, so pads can
## join and drop out at runtime without any action remapping.
##
## The binding table is deliberately tunable: the eight frequent inputs live on
## face buttons, bumpers and triggers, while the two deliberate ones (interact,
## ultimate) sit on the d-pad where they cannot be fumbled mid-combo.
class_name GamepadInputSource
extends InputSource

const DEADZONE := 0.22
const TRIGGER_THRESHOLD := 0.5

const BUTTON_BINDINGS := {
	InputFrame.Action.JUMP: JOY_BUTTON_A,
	InputFrame.Action.LIGHT: JOY_BUTTON_X,
	InputFrame.Action.HEAVY: JOY_BUTTON_Y,
	InputFrame.Action.GRAB: JOY_BUTTON_B,
	InputFrame.Action.BLOCK: JOY_BUTTON_LEFT_SHOULDER,
	InputFrame.Action.LAUNCHER: JOY_BUTTON_RIGHT_SHOULDER,
	InputFrame.Action.INTERACT: JOY_BUTTON_DPAD_UP,
	InputFrame.Action.ULTIMATE: JOY_BUTTON_DPAD_DOWN,
}

## Buttons driven by an analog trigger rather than a digital press.
const TRIGGER_BINDINGS := {
	InputFrame.Action.DODGE: JOY_AXIS_TRIGGER_LEFT,
	InputFrame.Action.SIGNATURE: JOY_AXIS_TRIGGER_RIGHT,
}

## Any of these claims an unassigned pad at the join prompt.
const JOIN_BUTTONS := [JOY_BUTTON_A, JOY_BUTTON_START]

var device: int


func _init(device_id: int) -> void:
	device = device_id


func _read(f: InputFrame) -> void:
	f.move = _stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	f.aim = _stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if f.aim == Vector2.ZERO:
		f.aim = f.move

	for action: InputFrame.Action in BUTTON_BINDINGS:
		f.set_action(action, Input.is_joy_button_pressed(device, BUTTON_BINDINGS[action]))

	for action: InputFrame.Action in TRIGGER_BINDINGS:
		var pull := Input.get_joy_axis(device, TRIGGER_BINDINGS[action])
		f.set_action(action, pull >= TRIGGER_THRESHOLD)


## Radial deadzone, so diagonals are not clipped into the cardinals the way a
## per-axis deadzone would clip them.
func _stick(axis_x: JoyAxis, axis_y: JoyAxis) -> Vector2:
	var raw := Vector2(
		Input.get_joy_axis(device, axis_x),
		-Input.get_joy_axis(device, axis_y)  # stick up reads negative
	)
	var magnitude := raw.length()
	if magnitude < DEADZONE:
		return Vector2.ZERO
	# Rescale past the deadzone so the usable range still reaches full tilt.
	var scaled := (magnitude - DEADZONE) / (1.0 - DEADZONE)
	return raw.normalized() * minf(scaled, 1.0)


func get_display_name() -> String:
	var pad_name := Input.get_joy_name(device)
	return pad_name if pad_name != "" else "Gamepad %d" % device


func get_device_id() -> int:
	return device


func is_device_connected() -> bool:
	return Input.get_connected_joypads().has(device)


static func is_join_requested(device_id: int) -> bool:
	for button: JoyButton in JOIN_BUTTONS:
		if Input.is_joy_button_pressed(device_id, button):
			return true
	return false
