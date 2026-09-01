## One tick of intent from one player.
##
## Fighters consume InputFrame and never poll Input directly. That discipline
## keeps every gameplay state change flowing through a single serialisable
## struct, which is what a future online port would send over the wire.
class_name InputFrame
extends RefCounted

enum Action {
	LIGHT,
	HEAVY,
	LAUNCHER,
	GRAB,
	BLOCK,
	DODGE,
	JUMP,
	INTERACT,
	SIGNATURE,
	ULTIMATE,
}

## Movement intent. x is right, y is forward (stick up is +1), length <= 1.
var move := Vector2.ZERO
## Aim intent for powers, same convention as move.
var aim := Vector2.ZERO

var _held: int = 0
var _previous: int = 0

## Called by the input source before it reads the device.
func begin_frame() -> void:
	_previous = _held
	_held = 0
	move = Vector2.ZERO
	aim = Vector2.ZERO


func set_action(action: Action, down: bool) -> void:
	if down:
		_held |= 1 << action


func is_held(action: Action) -> bool:
	return _held & (1 << action) != 0


## Makes this frame's held state also its previous state, so nothing in it reads
## as a fresh press. Used when a source is first polled.
func carry_forward() -> void:
	_previous = _held


func is_just_pressed(action: Action) -> bool:
	return _held & ~_previous & (1 << action) != 0


func is_just_released(action: Action) -> bool:
	return ~_held & _previous & (1 << action) != 0


## Zeroes intent without losing edge detection -- used when a pad disconnects
## so the fighter coasts to a stop instead of running off with a stuck stick.
func clear() -> void:
	_previous = _held
	_held = 0
	move = Vector2.ZERO
	aim = Vector2.ZERO


func has_any_input() -> bool:
	return _held != 0 or move != Vector2.ZERO
