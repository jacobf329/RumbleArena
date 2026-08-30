## M1 test harness HUD.
##
## Deliberately plain text: this milestone exists to answer "does the camera
## hold up and does moving feel good", and numbers answer that faster than art.
extends Control

const JOIN_HINT := "Press [A] on a gamepad, or [SPACE] on the keyboard, to join."

@onready var _join_label: Label = $Margin/Rows/JoinHint
@onready var _players_label: Label = $Margin/Rows/Players
@onready var _controls_label: Label = $Margin/Rows/Controls

var fighters: Array[Fighter] = []


func _ready() -> void:
	_controls_label.text = _controls_text()


func _process(_delta: float) -> void:
	var free_seats: int = PlayerManager.MAX_PLAYERS - PlayerManager.get_active_count()
	_join_label.text = "%s   (%d seat%s open)" % [
		JOIN_HINT, free_seats, "" if free_seats == 1 else "s"
	] if free_seats > 0 else "All four seats filled."

	var lines: Array[String] = []
	for slot: PlayerSlot in PlayerManager.slots:
		if not slot.is_active():
			lines.append("%s  --  empty" % slot.get_label())
		elif slot.is_awaiting_reconnect():
			lines.append("%s  !!  reconnect %s" % [slot.get_label(), slot.source.get_display_name()])
		else:
			lines.append(_fighter_line(slot))
	_players_label.text = "\n".join(lines)


func _fighter_line(slot: PlayerSlot) -> String:
	for fighter in fighters:
		if is_instance_valid(fighter) and fighter.slot == slot:
			return fighter.get_debug_line()
	return "%s  --  joined (%s)" % [slot.get_label(), slot.source.get_display_name()]


func _controls_text() -> String:
	return "Gamepad: stick move | A jump | LT dash | X light | Y heavy | RB launcher | B grab | LB block\n" \
		+ "Keyboard: WASD move | SPACE jump | SHIFT dash | J light | K heavy | L launcher | U grab | CTRL block"
