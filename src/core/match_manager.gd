## Owns the shape of a match: stocks, eliminations, and who won.
##
## Fighters do not decide their own fate. A fighter reports that it was defeated
## and stops there; this decides whether that costs a stock and a respawn or ends
## someone's match. Keeping that call in one place is what makes "last ninja
## standing" a rule rather than something scattered across the fighter class.
class_name MatchManager
extends Node

enum Phase {
	WAITING,    ## Players joining; hits land but nothing is at stake.
	COUNTDOWN,  ## Enough players are in; the fight is about to start.
	FIGHTING,   ## Stocks count.
	VICTORY,    ## Somebody won; everyone is frozen until the reset.
}

## Fewest players a match can start with.
const MIN_PLAYERS := 2

@export var stocks_per_player: int = 3
## Restarts whenever another player joins, so nobody is locked out by being late.
@export var countdown_seconds: float = 4.0
@export var match_seconds: float = 180.0
## Invulnerability on respawn, so a stock is not lost to whoever is standing on
## the spawn point.
@export var respawn_invulnerable_ticks: int = 100
@export var victory_seconds: float = 7.0
## Off in tests that are about something other than match flow: they drive
## fighters directly, and a countdown that repositions everyone mid-test would
## make them measure the match rather than what they are checking.
@export var auto_start: bool = true

signal phase_changed(phase: Phase)
signal stock_lost(slot: PlayerSlot, remaining: int)
signal player_eliminated(slot: PlayerSlot)
## Winner is null when the timer runs out on a tie.
signal match_ended(winner: PlayerSlot)

var phase: Phase = Phase.WAITING
var time_left: float = 0.0
var winner: PlayerSlot = null

var _stocks: Dictionary = {}
var _fighters: Dictionary = {}


func register(fighter: Fighter) -> void:
	if fighter.slot == null:
		return
	var index := fighter.slot.index
	_fighters[index] = fighter
	_stocks[index] = stocks_per_player
	fighter.defeated.connect(_on_fighter_defeated.bind(fighter))

	# A player who joins during the countdown restarts it; one who joins
	# mid-match waits for the next one rather than dropping in at a deficit.
	if phase == Phase.WAITING or phase == Phase.COUNTDOWN:
		_evaluate_start()


func get_stocks(index: int) -> int:
	return _stocks.get(index, 0)


func is_eliminated(index: int) -> bool:
	return _stocks.get(index, 0) <= 0


func get_living_slots() -> Array[PlayerSlot]:
	var living: Array[PlayerSlot] = []
	for index: int in _fighters:
		if not is_eliminated(index):
			living.append((_fighters[index] as Fighter).slot)
	return living


func _process(delta: float) -> void:
	match phase:
		Phase.COUNTDOWN:
			time_left -= delta
			if time_left <= 0.0:
				_begin_fight()
		Phase.FIGHTING:
			time_left -= delta
			if time_left <= 0.0:
				_end_match(_leader_on_stocks())
		Phase.VICTORY:
			time_left -= delta
			if time_left <= 0.0:
				_reset_to_waiting()


## A match waits for everyone who has joined to lock in, not just for enough
## bodies. Somebody still deciding should never be dropped into a countdown.
func _evaluate_start() -> void:
	if not auto_start:
		_set_phase(Phase.WAITING)
		return
	if _fighters.size() < MIN_PLAYERS or not _everyone_ready():
		_set_phase(Phase.WAITING)
		return
	time_left = countdown_seconds
	_set_phase(Phase.COUNTDOWN)


func _everyone_ready() -> bool:
	for index: int in _fighters:
		var fighter := _fighters[index] as Fighter
		if fighter.slot != null and not fighter.slot.is_ready:
			return false
	return true


## Called by character select whenever somebody readies up or changes their
## mind. Un-readying during a countdown puts the match back to waiting.
func refresh_readiness() -> void:
	if phase == Phase.WAITING or phase == Phase.COUNTDOWN:
		_evaluate_start()


func _begin_fight() -> void:
	for index: int in _fighters:
		_stocks[index] = stocks_per_player
		var fighter := _fighters[index] as Fighter
		fighter.respawn()
		fighter.grant_invulnerability(respawn_invulnerable_ticks)
	time_left = match_seconds
	winner = null
	_set_phase(Phase.FIGHTING)


## Nothing is at stake before the fight, so a knockout during warm-up just puts
## the fighter back on their feet.
func _on_fighter_defeated(fighter: Fighter) -> void:
	if phase != Phase.FIGHTING:
		fighter.respawn()
		fighter.grant_invulnerability(respawn_invulnerable_ticks)
		return

	var index := fighter.slot.index
	_stocks[index] = maxi(_stocks.get(index, 0) - 1, 0)
	stock_lost.emit(fighter.slot, _stocks[index])

	if _stocks[index] > 0:
		fighter.respawn()
		fighter.grant_invulnerability(respawn_invulnerable_ticks)
		return

	fighter.eliminate()
	player_eliminated.emit(fighter.slot)

	var living := get_living_slots()
	if living.size() <= 1:
		_end_match(living[0] if living.size() == 1 else null)


## On a timeout the most stocks wins; an exact tie is a draw rather than an
## arbitrary winner.
func _leader_on_stocks() -> PlayerSlot:
	var best := -1
	var leader: PlayerSlot = null
	var tied := false
	for index: int in _fighters:
		var count: int = _stocks.get(index, 0)
		if count > best:
			best = count
			leader = (_fighters[index] as Fighter).slot
			tied = false
		elif count == best:
			tied = true
	return null if tied else leader


func _end_match(won_by: PlayerSlot) -> void:
	winner = won_by
	time_left = victory_seconds
	_set_phase(Phase.VICTORY)
	match_ended.emit(won_by)


func _reset_to_waiting() -> void:
	for index: int in _fighters:
		var fighter := _fighters[index] as Fighter
		fighter.restore()
		_stocks[index] = stocks_per_player
	winner = null
	for index: int in _fighters:
		var fighter := _fighters[index] as Fighter
		if fighter.slot != null:
			fighter.slot.is_ready = false
	_evaluate_start()


func _set_phase(next: Phase) -> void:
	if phase == next:
		return
	phase = next
	phase_changed.emit(phase)


func phase_name() -> String:
	return Phase.keys()[phase]
