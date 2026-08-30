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
	else:
		frame.clear()


## Override to fill the frame from the device.
func _read(_frame: InputFrame) -> void:
	pass


func get_display_name() -> String:
	return "Unassigned"


func get_device_id() -> int:
	return KEYBOARD_DEVICE


func is_device_connected() -> bool:
	return true


## True if this source is already driven by the given device, so PlayerManager
## does not hand the same pad to two slots.
func owns_device(device_id: int) -> bool:
	return get_device_id() == device_id
