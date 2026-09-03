## After the fight: what happened, and what you can do about it.
##
## Losing offers the same chapter again as the first item, because the thing you
## want after a loss is another go, not a menu. Winning offers the next chapter
## in the same position for the same reason.
class_name OutcomeScreen
extends Control

signal retry_requested
signal continue_requested
signal back_requested
signal menu_requested

## Set by the router before this enters the tree.
var chapter: StoryChapter
var chapter_number := 0
var won := false
var has_next := false

@onready var _banner: Label = $Layout/Banner
@onready var _title: Label = $Layout/Title
@onready var _prose: Label = $Layout/Prose
@onready var _items: VBoxContainer = $Layout/Items
@onready var _hint: Label = $Layout/Hint

var _options: Array[StringName] = []
var _labels: Array[Label] = []
var _cursor := 0
var _input := MenuInput.new()


func _ready() -> void:
	_banner.text = "CHAPTER CLEARED" if won else "DEFEATED"
	_banner.modulate = Color(0.55, 0.95, 0.62) if won else Color(0.94, 0.5, 0.45)
	if chapter != null:
		_title.text = "%d.  %s" % [chapter_number + 1, chapter.title]
		_prose.text = chapter.victory if won else chapter.defeat

	_options = _build_options()
	for option in _options:
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 30)
		_items.add_child(label)
		_labels.append(label)
	_hint.text = "[W/S] choose    [SPACE] or [A] confirm"
	_refresh()


## Won and there is more: forward. Won and there is not: the campaign is over,
## so there is nothing to go forward to. Lost: again.
func _build_options() -> Array[StringName]:
	if won:
		if has_next:
			return [&"next", &"chapters", &"menu"]
		return [&"chapters", &"menu"]
	return [&"retry", &"chapters", &"menu"]


func _physics_process(delta: float) -> void:
	_input.poll(delta)
	if _input.just_pressed(MenuInput.Action.UP):
		_move(-1)
	elif _input.just_pressed(MenuInput.Action.DOWN):
		_move(1)
	elif _input.just_pressed(MenuInput.Action.CONFIRM):
		_choose()
	elif _input.just_pressed(MenuInput.Action.BACK):
		back_requested.emit()


func _move(direction: int) -> void:
	_cursor = wrapi(_cursor + direction, 0, _options.size())
	_refresh()


func _choose() -> void:
	match _options[_cursor]:
		&"next":
			continue_requested.emit()
		&"retry":
			retry_requested.emit()
		&"chapters":
			back_requested.emit()
		&"menu":
			menu_requested.emit()


func _refresh() -> void:
	for i in _labels.size():
		_labels[i].text = "%s%s" % ["> " if i == _cursor else "   ", _label_for(_options[i])]
		_labels[i].modulate = Color(1.0, 0.86, 0.5) if i == _cursor else Color(0.78, 0.82, 0.9)


func _label_for(option: StringName) -> String:
	match option:
		&"next": return "Next chapter"
		&"retry": return "Try again"
		&"chapters": return "Chapter select"
		&"menu": return "Main menu"
	return ""
