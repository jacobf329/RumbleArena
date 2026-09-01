## One of the four columns on the character select screen.
##
## Shows what a seat is: empty and waiting, browsing, or locked in. The stat bars
## are the point of the screen -- a roster where everybody has a 4 or 5 somewhere
## and a 2 or below somewhere else only reads as asymmetric if you can see the
## shape of it before you commit.
class_name SeatPanel
extends PanelContainer

const STAT_ORDER := [
	Stats.Type.STRENGTH, Stats.Type.SPEED, Stats.Type.AGILITY,
	Stats.Type.TECH, Stats.Type.FOCUS, Stats.Type.TOUGHNESS,
]
## Filled and empty pips, so a 2 reads as "two of five" rather than a short bar.
const PIP_FULL := "|"
const PIP_EMPTY := "."

@onready var _seat_label: Label = $Rows/Seat
@onready var _preview: CharacterPreview = $Rows/Preview
@onready var _name_label: Label = $Rows/Name
@onready var _epithet: Label = $Rows/Epithet
@onready var _concept: Label = $Rows/Concept
@onready var _stats: VBoxContainer = $Rows/Stats
@onready var _powers: Label = $Rows/Powers
@onready var _status: Label = $Rows/Status

var _stat_rows: Dictionary = {}


func _ready() -> void:
	for stat: Stats.Type in STAT_ORDER:
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 17)
		_stats.add_child(row)
		_stat_rows[stat] = row


func show_empty(slot: PlayerSlot) -> void:
	_seat_label.text = "P%d" % (slot.index + 1)
	_seat_label.modulate = Color(0.4, 0.43, 0.5)
	_name_label.text = ""
	_epithet.text = ""
	_concept.text = ""
	_powers.text = ""
	for stat: Stats.Type in STAT_ORDER:
		(_stat_rows[stat] as Label).text = ""
	_status.text = "Press [A] or [SPACE]\nto join"
	_status.modulate = Color(0.62, 0.68, 0.8)
	_preview.hide()
	modulate = Color(0.62, 0.62, 0.68)


func show_character(slot: PlayerSlot, definition: CharacterDef) -> void:
	# A bot's seat already reads CPU3; adding the device name after it just says
	# CPU twice.
	_seat_label.text = slot.get_label() if slot.is_bot() \
		else "%s   %s" % [slot.get_label(), slot.source.get_display_name()]
	_seat_label.modulate = slot.color
	_preview.show()
	_preview.set_character(definition, slot.color)

	_name_label.text = definition.display_name
	_name_label.modulate = slot.color
	# Quotes only when there is something to put in them.
	_epithet.text = "\"%s\"" % definition.epithet if definition.epithet != "" else ""
	_concept.text = definition.concept

	for stat: Stats.Type in STAT_ORDER:
		var value := definition.get_stat(stat)
		var row := _stat_rows[stat] as Label
		row.text = "%-10s %s%s  %d" % [
			Stats.display_name(stat), PIP_FULL.repeat(value),
			PIP_EMPTY.repeat(5 - value), value,
		]
		# The extremes are what make a ninja worth picking or worth avoiding, so
		# they are the only ones coloured.
		if value >= 4:
			row.modulate = Color(0.55, 0.95, 0.62)
		elif value <= 2:
			row.modulate = Color(0.92, 0.5, 0.45)
		else:
			row.modulate = Color(0.72, 0.76, 0.86)

	_powers.text = "RT  %s\nR3  %s" % [
		definition.signature.display_name if definition.signature != null else "-",
		definition.ultimate.display_name if definition.ultimate != null else "-",
	]

	if slot.is_ready:
		_status.text = "READY\n[B] to change"
		_status.modulate = Color(0.55, 0.95, 0.62)
	else:
		_status.text = "[LB] / [RB] or left / right\n[A] to lock in"
		_status.modulate = Color(0.78, 0.82, 0.92)

	_preview.set_dimmed(false)
	modulate = Color.WHITE
