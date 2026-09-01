## The front door.
##
## Deliberately shows the locked entries rather than hiding them: a menu with
## one item on it tells you nothing about what the game is going to be, and
## "Story  --  coming soon" is information. The same reasoning as the greyed-out
## interaction prompts in the arena, which name the requirement they refuse.
extends Control

signal play_requested
signal quit_requested

const ITEMS := [
	{"label": "Local Versus", "detail": "Up to four ninjas, one screen, one camera.", "enabled": true},
	{"label": "Story", "detail": "Coming soon.", "enabled": false},
	{"label": "Controls", "detail": "How to play.", "enabled": true},
	{"label": "Quit", "detail": "", "enabled": true},
]

@onready var _rows: VBoxContainer = $Layout/Menu/Items
@onready var _detail: Label = $Layout/Menu/Detail
@onready var _controls_panel: Control = $Controls
@onready var _hint: Label = $Layout/Hint

var _cursor := 0
var _showing_controls := false
var _input := MenuInput.new()
var _labels: Array[Label] = []


func _ready() -> void:
	for item in ITEMS:
		var label := Label.new()
		label.text = item["label"]
		label.add_theme_font_size_override("font_size", 34)
		_rows.add_child(label)
		_labels.append(label)
	_controls_panel.hide()
	_refresh()


## On the physics tick, not the render frame -- the same rule PlayerManager
## follows for exactly the same reason. Just-pressed edges are only meaningful
## if they are produced at the rate they are consumed, and a menu polled on a
## variable frame has repeat timing that changes with the frame rate.
func _physics_process(delta: float) -> void:
	_input.poll(delta)

	if _showing_controls:
		if _input.just_pressed(MenuInput.Action.BACK) \
				or _input.just_pressed(MenuInput.Action.CONFIRM):
			_showing_controls = false
			_controls_panel.hide()
		return

	if _input.just_pressed(MenuInput.Action.UP):
		_move(-1)
	elif _input.just_pressed(MenuInput.Action.DOWN):
		_move(1)
	elif _input.just_pressed(MenuInput.Action.CONFIRM):
		_choose()


## Skips past anything locked, so holding down never parks the cursor on an
## entry that will not answer.
func _move(direction: int) -> void:
	for step in ITEMS.size():
		_cursor = wrapi(_cursor + direction, 0, ITEMS.size())
		if ITEMS[_cursor]["enabled"]:
			break
	_refresh()


func _choose() -> void:
	if not ITEMS[_cursor]["enabled"]:
		return
	match ITEMS[_cursor]["label"]:
		"Local Versus":
			play_requested.emit()
		"Controls":
			_showing_controls = true
			_controls_panel.show()
		"Quit":
			quit_requested.emit()


func _refresh() -> void:
	for i in _labels.size():
		var label := _labels[i]
		var enabled: bool = ITEMS[i]["enabled"]
		var selected := i == _cursor
		label.text = "%s%s%s" % [
			"> " if selected else "   ",
			ITEMS[i]["label"],
			"" if enabled else "   -  coming soon",
		]
		if not enabled:
			label.modulate = Color(0.45, 0.46, 0.5)
		elif selected:
			label.modulate = Color(1.0, 0.86, 0.5)
		else:
			label.modulate = Color(0.78, 0.82, 0.9)
	_detail.text = ITEMS[_cursor]["detail"]
	_hint.text = "[W/S] or stick to move    [SPACE] or [A] to choose"
