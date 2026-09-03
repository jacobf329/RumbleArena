## The words before the fight.
##
## A separate screen from chapter select rather than a panel on it, because the
## briefing is the only place the story is actually told and prose read at a
## glance while a cursor is moving is prose nobody reads. Nothing here is
## interactive except leaving and starting: it is a page.
class_name BriefingScreen
extends Control

signal fight_requested
signal back_requested

## Set by the router before this is added to the tree, so _ready can draw once
## rather than the screen having to render itself twice.
var chapter: StoryChapter
var chapter_number := 0
var character_index := 0

@onready var _title: Label = $Layout/Title
@onready var _location: Label = $Layout/Location
@onready var _briefing: Label = $Layout/Briefing
@onready var _lineup: VBoxContainer = $Layout/Body/Lineup/Rows
@onready var _preview: CharacterPreview = $Layout/Body/You/Preview
@onready var _you_name: Label = $Layout/Body/You/Name
@onready var _you_stocks: Label = $Layout/Body/You/Stocks
@onready var _hint: Label = $Layout/Hint

var _input := MenuInput.new()


func _ready() -> void:
	if chapter == null:
		return
	_title.text = "%d.  %s" % [chapter_number + 1, chapter.title]
	_location.text = chapter.location
	_briefing.text = chapter.briefing

	for opponent in chapter.get_opponents():
		_lineup.add_child(_opponent_row(opponent))

	var definition := CharacterRoster.at(character_index)
	_preview.set_character(definition, PlayerManager.SLOT_COLORS[0])
	_you_name.text = definition.display_name
	_you_stocks.text = "%d stock%s\n%s" % [
		chapter.player_stocks,
		"" if chapter.player_stocks == 1 else "s",
		definition.get_stat_line(),
	]
	_hint.text = "[SPACE] or [A] fight    [ESC] or [B] back"


func driving_device() -> int:
	return _input.last_device


func _physics_process(delta: float) -> void:
	_input.poll(delta)
	if _input.just_pressed(MenuInput.Action.BACK):
		back_requested.emit()
	elif _input.just_pressed(MenuInput.Action.CONFIRM):
		fight_requested.emit()


## Name, stocks and one line about them. The note is what stops a lineup reading
## as a difficulty table.
func _opponent_row(opponent: StoryOpponent) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	name_label.add_theme_font_size_override("font_size", 27)
	name_label.text = "%s   x%d stock%s" % [
		opponent.display_name(), opponent.stocks,
		"" if opponent.stocks == 1 else "s",
	]
	name_label.modulate = Color(0.94, 0.6, 0.55)
	box.add_child(name_label)

	var note := Label.new()
	note.add_theme_font_size_override("font_size", 18)
	note.modulate = Color(0.66, 0.7, 0.82)
	note.text = opponent.note
	box.add_child(note)

	var stats := Label.new()
	stats.add_theme_font_size_override("font_size", 16)
	stats.modulate = Color(0.55, 0.6, 0.72)
	stats.text = opponent.character.get_stat_line()
	box.add_child(stats)

	return box
