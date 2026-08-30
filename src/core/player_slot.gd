## One of the four player seats: who is holding what, and which fighter it drives.
class_name PlayerSlot
extends RefCounted

var index: int
var source: InputSource = null
var fighter: Node3D = null
var color: Color = Color.WHITE

## Which character this seat has picked, and whether they have locked it in.
## Defaults to the seat's own number so a player who never touches select still
## gets somebody, and four players still get four different ninjas.
var character_index: int = 0
var is_ready: bool = false


func _init(slot_index: int, slot_color: Color) -> void:
	index = slot_index
	color = slot_color
	character_index = slot_index


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
