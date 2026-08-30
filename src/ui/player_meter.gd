## One player's health, power and stamina.
##
## Health is the big bar because it is the only one that ends a match. Power and
## stamina share a thinner row: they matter constantly but never fatally.
class_name PlayerMeter
extends PanelContainer

var _fighter: Fighter

@onready var _name_label: Label = $Rows/Name
@onready var _health: ProgressBar = $Rows/Health
@onready var _power: ProgressBar = $Rows/Small/Power
@onready var _stamina: ProgressBar = $Rows/Small/Stamina


func bind(fighter: Fighter) -> void:
	_fighter = fighter
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

	_health.max_value = fighter.max_health
	_power.max_value = fighter.max_power
	_stamina.max_value = fighter.max_stamina


func _process(_delta: float) -> void:
	if not is_instance_valid(_fighter):
		return
	_health.value = _fighter.health
	_power.value = _fighter.power
	_stamina.value = _fighter.stamina
