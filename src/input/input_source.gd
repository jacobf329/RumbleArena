## Base for anything that can drive one player.
##
## Subclasses fill an InputFrame from a concrete device. PlayerManager owns the
## sources and polls them once per physics tick, before fighters read them.
class_name InputSource
extends RefCounted

const KEYBOARD_DEVICE := -1

var frame := InputFrame.new()


func poll() -> void:
	frame.begin_frame()
	if is_device_connected():
		_read(frame)
	# Otherwise the frame stays as begin_frame() left it: nothing held, previous
	# state intact, so a release edge still fires for whatever was down.


## Override to fill the frame from the device.
func _read(_frame: InputFrame) -> void:
	pass


func get_display_name() -> String:
	return "Unassigned"


## What this device calls the button for an action, for prompts like
## "[B] Throw Concrete Pillar".
##
## Asked of the source rather than hardcoded in the HUD because four seats can
## be on four different devices at once, and a prompt that named the wrong
## button would be worse than naming none -- which is what it did before, and is
## how you end up with a player who can pick things up and has no idea they can
## put them down again.
func button_hint(_action: InputFrame.Action) -> String:
	return ""


func get_device_id() -> int:
	return KEYBOARD_DEVICE


func is_device_connected() -> bool:
	return true


## True if this source is already driven by the given device, so PlayerManager
## does not hand the same pad to two slots.
func owns_device(device_id: int) -> bool:
	return get_device_id() == device_id


## Haptics. A no-op on devices that cannot buzz.
func rumble(_weak: float, _strong: float, _duration: float) -> void:
	pass


func stop_rumble() -> void:
	pass
