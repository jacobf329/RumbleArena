## One player's health, power and stamina.
##
## Health is the big bar because it is the only one that ends a match. Power and
## stamina share a thinner row: they matter constantly but never fatally.
class_name PlayerMeter
extends PanelContainer

## Filled and spent stock pips. Spent ones stay visible so the bar reads as
## "two of three left" rather than just getting shorter.
const PIP_LEFT := "●"
const PIP_SPENT := "○"

var _fighter: Fighter
var _match: MatchManager

@onready var _name_label: Label = $Rows/Name
@onready var _stocks_label: Label = $Rows/Stocks
@onready var _health: ProgressBar = $Rows/Health
@onready var _power: ProgressBar = $Rows/Small/Power
@onready var _stamina: ProgressBar = $Rows/Small/Stamina


func bind(fighter: Fighter, manager: MatchManager = null) -> void:
	_fighter = fighter
	_match = manager
	if not is_node_ready():
		await ready

	var slot := fighter.slot
	_name_label.text = "%s   %s" % [
		slot.get_label() if slot != null else "--",
		fighter.character_def.display_name,
	]
	# Slot colour on the name, not on the bars: a health bar that changed colour
	# per player would stop reading as a health bar.
	if slot != null:
		_name_label.modulate = slot.color

	_refresh_ranges()


func get_fighter() -> Fighter:
	return _fighter


func _process(_delta: float) -> void:
	if not is_instance_valid(_fighter):
		return
	# Read the ranges every frame rather than caching them: a character swap in
	# select changes the maximums under us.
	_refresh_ranges()
	_name_label.text = "%s   %s" % [
		_fighter.slot.get_label() if _fighter.slot != null else "--",
		_fighter.character_def.display_name,
	]
	_health.value = _fighter.health
	_power.value = _fighter.power
	_stamina.value = _fighter.stamina
	_update_stocks()


func _refresh_ranges() -> void:
	_health.max_value = _fighter.max_health
	_power.max_value = _fighter.max_power
	_stamina.max_value = _fighter.max_stamina


func _update_stocks() -> void:
	if _match == null or _fighter.slot == null:
		_stocks_label.text = ""
		return
	var left: int = _match.get_stocks(_fighter.slot.index)
	var total: int = _match.stocks_per_player
	_stocks_label.text = PIP_LEFT.repeat(left) + PIP_SPENT.repeat(maxi(total - left, 0))
	# A knocked-out player's whole panel dims, so at a glance the screen shows
	# who is still in it.
	modulate = Color(1, 1, 1, 0.4) if left <= 0 else Color.WHITE
