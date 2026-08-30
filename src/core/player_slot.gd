## One of the four player seats: who is holding what, and which fighter it drives.
class_name PlayerSlot
extends RefCounted

var index: int
var source: InputSource = null
var fighter: Node3D = null
var color: Color = Color.WHITE


func _init(slot_index: int, slot_color: Color) -> void:
	index = slot_index
	color = slot_color


func is_active() -> bool:
	return source != null


## An active slot whose pad has been unplugged. The seat stays reserved so the
## player can plug back in and carry on rather than losing their fighter.
func is_awaiting_reconnect() -> bool:
	return source != null and not source.is_device_connected()


func get_frame() -> InputFrame:
	return source.frame if source != null else null


func get_label() -> String:
	return "P%d" % (index + 1)
