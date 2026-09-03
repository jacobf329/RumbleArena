## Chapter select for the campaign.
##
## Locked chapters are shown, and the cursor is allowed to stop on them. That is
## the same call the interaction prompts make in the arena: being refused with
## the reason attached teaches the shape of the thing, and a list that hid what
## you have not reached yet would say nothing about how long the climb is.
##
## Your ninja is picked here rather than on a separate screen. There is one seat
## in story mode, so a whole character select for it would be three panels of
## empty and one of you.
class_name StoryScreen
extends Control

signal chapter_chosen(chapter_index: int, character_index: int)
signal back_requested

## Seconds a refusal stays on screen after you try a locked chapter.
const REFUSAL_SECONDS := 2.5

## Set by the router so a ninja picked once survives the trip through a fight.
var character_index := 0

@onready var _heading: Label = $Layout/Heading
@onready var _premise: Label = $Layout/Premise
@onready var _chapters: VBoxContainer = $Layout/Body/Left/Chapters
@onready var _detail_title: Label = $Layout/Body/Detail/Title
@onready var _detail_location: Label = $Layout/Body/Detail/Location
@onready var _detail_briefing: Label = $Layout/Body/Detail/Briefing
@onready var _detail_lineup: Label = $Layout/Body/Detail/Lineup
@onready var _preview: CharacterPreview = $Layout/Body/Ninja/Preview
@onready var _ninja_name: Label = $Layout/Body/Ninja/Name
@onready var _ninja_stats: Label = $Layout/Body/Ninja/Stats
@onready var _status: Label = $Layout/Status
@onready var _hint: Label = $Layout/Hint

var _campaign: StoryCampaign
var _cursor := 0
var _rows: Array[Label] = []
var _input := MenuInput.new()
var _refusal := 0.0


func _ready() -> void:
	_campaign = StoryCampaign.load_default()
	_heading.text = _campaign.title.to_upper()
	_premise.text = _campaign.premise

	for i in _campaign.size():
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 25)
		_chapters.add_child(row)
		_rows.append(row)

	# Opens on the fight you are actually up to, not on chapter one every time.
	_cursor = clampi(StoryProgress.cleared_count(), 0, maxi(_campaign.size() - 1, 0))
	_refresh()


## Which device has been driving this screen, so the router can seat it rather
## than making a player who has been holding a pad for five minutes press join.
func driving_device() -> int:
	return _input.last_device


## Physics tick, matching every other screen: a just-pressed edge read on a
## render frame is an edge produced at a rate nothing else in the game uses.
func _physics_process(delta: float) -> void:
	_input.poll(delta)
	_refusal = maxf(_refusal - delta, 0.0)

	if _input.just_pressed(MenuInput.Action.BACK):
		back_requested.emit()
		return
	if _input.just_pressed(MenuInput.Action.UP):
		_move(-1)
	elif _input.just_pressed(MenuInput.Action.DOWN):
		_move(1)
	elif _input.just_pressed(MenuInput.Action.LEFT):
		_cycle(-1)
	elif _input.just_pressed(MenuInput.Action.RIGHT):
		_cycle(1)
	elif _input.just_pressed(MenuInput.Action.CONFIRM):
		_choose()
	else:
		_status.text = _status_text()
		return
	_refresh()


func _move(direction: int) -> void:
	if _campaign.size() == 0:
		return
	_cursor = wrapi(_cursor + direction, 0, _campaign.size())


func _cycle(direction: int) -> void:
	character_index = CharacterRoster.step(character_index, direction)


func _choose() -> void:
	if StoryProgress.is_unlocked(_cursor):
		chapter_chosen.emit(_cursor, character_index)
		return
	# Refused rather than silent. The list already says which chapter is next;
	# this says it again at the moment the player disagreed with it.
	_refusal = REFUSAL_SECONDS


func _refresh() -> void:
	for i in _rows.size():
		var chapter := _campaign.at(i)
		var row := _rows[i]
		var selected := i == _cursor
		var unlocked := StoryProgress.is_unlocked(i)
		row.text = "%s%d.  %s%s" % [
			"> " if selected else "   ",
			i + 1,
			chapter.title,
			"   [CLEARED]" if StoryProgress.is_cleared(i) else ("" if unlocked else "   [LOCKED]"),
		]
		if not unlocked:
			row.modulate = Color(0.42, 0.44, 0.5)
		elif selected:
			row.modulate = Color(1.0, 0.86, 0.5)
		elif StoryProgress.is_cleared(i):
			row.modulate = Color(0.55, 0.8, 0.62)
		else:
			row.modulate = Color(0.78, 0.82, 0.9)

	var chapter := _campaign.at(_cursor)
	if chapter != null:
		_detail_title.text = "%d.  %s" % [_cursor + 1, chapter.title]
		_detail_location.text = chapter.location
		_detail_briefing.text = chapter.briefing
		_detail_lineup.text = "Against    %s\nYou get    %d stock%s" % [
			chapter.lineup(), chapter.player_stocks,
			"" if chapter.player_stocks == 1 else "s",
		]

	var definition := CharacterRoster.at(character_index)
	_preview.set_character(definition, PlayerManager.SLOT_COLORS[0])
	_ninja_name.text = definition.display_name
	_ninja_stats.text = _stat_block(definition)
	_status.text = _status_text()
	_hint.text = "[W/S] chapter    [A/D] your ninja    [SPACE] or [A] begin    [ESC] or [B] back"


## Borrows the select screen's stat rows rather than inventing a second way of
## drawing the same six numbers -- the pips and their order are defined once, on
## SeatPanel, and a second copy would drift.
func _stat_block(definition: CharacterDef) -> String:
	var lines: Array[String] = []
	for stat: Stats.Type in SeatPanel.STAT_ORDER:
		var value := definition.get_stat(stat)
		lines.append("%-9s %s%s  %d" % [
			Stats.display_name(stat),
			SeatPanel.PIP_FULL.repeat(value),
			SeatPanel.PIP_EMPTY.repeat(5 - value),
			value,
		])
	return "\n".join(lines)


func _status_text() -> String:
	if _refusal > 0.0:
		return "Locked.  Clear chapter %d first." % (StoryProgress.cleared_count() + 1)
	var cleared := StoryProgress.cleared_count()
	if cleared >= _campaign.size():
		return "The Registry is yours.  All %d chapters cleared." % _campaign.size()
	return "%d of %d cleared." % [cleared, _campaign.size()]
