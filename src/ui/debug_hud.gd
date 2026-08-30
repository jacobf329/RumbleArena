## M1 test harness HUD.
##
## Deliberately plain text: this milestone exists to answer "does the camera
## hold up and does moving feel good", and numbers answer that faster than art.
extends Control

const JOIN_HINT := "Press [A] on a gamepad, or [SPACE] on the keyboard, to join."

const PLAYER_METER := preload("res://scenes/ui/player_meter.tscn")

@onready var _canary: Label = $Margin/Rows/ScriptCanary
@onready var _meters: HBoxContainer = $Meters
@onready var _join_label: Label = $Margin/Rows/JoinHint
@onready var _players_label: Label = $Margin/Rows/Players
@onready var _controls_label: Label = $Margin/Rows/Controls
@onready var _devices_label: Label = $Margin/Rows/Devices
@onready var _banner: Label = $Banner
@onready var _clock: Label = $Clock

var fighters: Array[Fighter] = []

var _match: MatchManager
## Seconds left showing "FIGHT!" after the countdown ends.
var _flash := 0.0


func _ready() -> void:
	_controls_label.text = _controls_text()
	_banner.text = ""
	_clock.text = ""


func bind_match(manager: MatchManager) -> void:
	_match = manager
	manager.phase_changed.connect(_on_phase_changed)


## Called by the match harness once a fighter exists, rather than by listening
## for player_joined -- the HUD is a child, so its _ready runs first and it
## would otherwise handle the signal before the fighter had been spawned.
func add_meter(fighter: Fighter) -> void:
	var meter: PlayerMeter = PLAYER_METER.instantiate()
	_meters.add_child(meter)
	meter.bind(fighter, _match)


## The mirror of add_meter, for a bot seat being emptied.
func remove_meter(fighter: Fighter) -> void:
	for child in _meters.get_children():
		var meter := child as PlayerMeter
		if meter != null and meter.get_fighter() == fighter:
			_meters.remove_child(meter)
			meter.queue_free()
			return


func _on_phase_changed(phase: MatchManager.Phase) -> void:
	if phase == MatchManager.Phase.FIGHTING:
		_flash = 1.2


## The warning the scene authors visible, and which this is the only thing that
## takes down.
##
## A broken class cache breaks the game in two different ways depending on which
## script it catches: sometimes this HUD script itself will not compile, in which
## case _process never runs and the warning simply stays up; sometimes it
## compiles but PlayerManager does not, and then the HUD looks normal while no
## button does anything. Checking for the autoload covers the second, and not
## running at all covers the first. Between them there is no way to reach the
## join screen with a dead input system and no explanation -- which is exactly
## what happened twice, and is unreadable without this.
func _input_system_is_alive() -> bool:
	return get_node_or_null(^"/root/PlayerManager") != null


func _process(delta: float) -> void:
	if not _input_system_is_alive():
		_canary.show()
		return
	_canary.hide()

	_flash = maxf(_flash - delta, 0.0)
	_update_match_ui()

	var free_seats: int = PlayerManager.MAX_PLAYERS - PlayerManager.get_active_count()
	_join_label.text = _join_text(free_seats)

	_devices_label.text = _devices_text()

	var lines: Array[String] = []
	for slot: PlayerSlot in PlayerManager.slots:
		if not slot.is_active():
			lines.append("%s  --  empty" % slot.get_label())
		elif slot.is_awaiting_reconnect():
			lines.append("%s  !!  reconnect %s" % [slot.get_label(), slot.source.get_display_name()])
		else:
			lines.append(_fighter_line(slot))
	_players_label.text = "\n".join(lines)


func _join_text(free_seats: int) -> String:
	if _match != null and _match.phase == MatchManager.Phase.WAITING \
			and PlayerManager.get_active_count() < MatchManager.MIN_PLAYERS:
		return "%s   Two players needed to start." % JOIN_HINT
	if free_seats <= 0:
		return "All four seats filled.   [BACK] or [F3] to free up a CPU seat."
	return "%s   (%d seat%s open)" % [JOIN_HINT, free_seats, "" if free_seats == 1 else "s"]


func _fighter_line(slot: PlayerSlot) -> String:
	for fighter in fighters:
		if is_instance_valid(fighter) and fighter.slot == slot:
			return fighter.get_debug_line()
	return "%s  --  joined (%s)" % [slot.get_label(), slot.source.get_display_name()]


## The banner carries the whole match state, because with four people on one
## couch nobody is reading a corner of the screen.
func _update_match_ui() -> void:
	if _match == null:
		return

	match _match.phase:
		MatchManager.Phase.WAITING:
			_banner.text = ""
			_clock.text = ""
		MatchManager.Phase.COUNTDOWN:
			_banner.text = str(maxi(ceili(_match.time_left), 1))
			_clock.text = ""
		MatchManager.Phase.FIGHTING:
			_banner.text = "FIGHT!" if _flash > 0.0 else ""
			_clock.text = _format_clock(_match.time_left)
		MatchManager.Phase.VICTORY:
			_clock.text = ""
			if _match.winner == null:
				_banner.text = "DRAW"
				_banner.modulate = Color.WHITE
			else:
				_banner.text = "%s WINS" % _match.winner.get_label()
				_banner.modulate = _match.winner.color


func _format_clock(seconds: float) -> String:
	var whole := maxi(ceili(seconds), 0)
	return "%d:%02d" % [whole / 60, whole % 60]


## Names every pad the engine can see. If a controller is plugged in and does
## not appear here, the problem is the driver or the cable, not the game.
func _devices_text() -> String:
	var pads := Input.get_connected_joypads()
	if pads.is_empty():
		return "Gamepads: none detected  (keyboard still works: press SPACE)"

	var described: Array[String] = []
	for device: int in pads:
		var name := Input.get_joy_name(device)
		described.append("%d: %s%s" % [
			device,
			name if name != "" else "unknown pad",
			"" if Input.is_joy_known(device) else " [no mapping]",
		])
	return "Gamepads: %d  -  %s" % [pads.size(), ", ".join(described)]


func _controls_text() -> String:
	return "Gamepad: stick/d-pad move | A jump | LT dodge | X light | Y heavy | RB launcher | B grab | LB block | RT signature | R3 ultimate\n" \
		+ "Keyboard: WASD move | SPACE jump | SHIFT dodge | J light | K heavy | L launcher | U grab | CTRL block | Q signature | R ultimate\n" \
		+ "Before the bell: [LB]/[RB] pick your ninja, [A] to lock in.\n" \
		+ "CPU opponents: [BACK] on a pad (clears the bench once the arena is full), or [F2] add / [F3] remove.  [F5] resets positions.\n" \
		+ "Light three times = punch, punch, KICK -- the kick throws a fireball if the blue meter can pay for it. Grab beats block."
