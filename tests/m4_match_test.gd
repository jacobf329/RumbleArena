## Headless verification of M4 match flow: stocks, elimination and victory.
##
## Fighters do not decide their own fate here -- the MatchManager does -- so
## these checks are mostly about who is allowed to end whose match, and when.
extends TestHarness

var _kurogane: Fighter
var _null: Fighter
var _jinsoku: Fighter

var _eliminations: Array[String] = []
var _ended := 0
var _last_winner: PlayerSlot = null


func _init() -> void:
	test_name = "M4 match test"


func _run() -> void:
	# Short phases so the whole match flow fits in a test rather than in a match.
	match_manager.countdown_seconds = 0.4
	match_manager.match_seconds = 60.0
	match_manager.victory_seconds = 0.4
	match_manager.stocks_per_player = 2

	match_manager.player_eliminated.connect(func(slot: PlayerSlot) -> void:
		_eliminations.append(slot.get_label()))
	match_manager.match_ended.connect(func(winner: PlayerSlot) -> void:
		_ended += 1
		_last_winner = winner)

	_section("Character select")
	await _test_seats_default_to_different_ninjas()
	await _test_cycling_changes_your_ninja()
	await _test_cycling_wraps_both_ways()
	await _test_locking_in_stops_you_cycling()

	_section("Starting a match")
	await _test_one_player_waits()
	await _test_nobody_starts_until_everyone_is_ready()
	await _test_a_late_join_sends_it_back_to_select()
	await _test_the_countdown_becomes_a_fight()

	_section("Stocks")
	await _test_warm_up_knockouts_are_free()
	await _test_a_knockout_costs_a_stock()
	await _test_respawning_is_briefly_invulnerable()

	_section("Elimination and victory")
	await _test_running_out_eliminates()
	await _test_the_camera_drops_eliminated_fighters()
	await _test_last_standing_wins()
	await _test_victory_resets_for_a_rematch()


# --- Character select ---

## Four seats give four different ninjas without anyone touching select, so a
## group that just mashes A still gets the asymmetry the game is about.
func _test_seats_default_to_different_ninjas() -> void:
	match_manager.auto_start = true
	character_select.enabled = true
	_kurogane = await _join(0)
	_null = await _join(1)
	await _ticks(6)

	_check(_kurogane.character_def.display_name != _null.character_def.display_name,
		"two seats start on different ninjas (%s, %s)"
			% [_kurogane.character_def.display_name, _null.character_def.display_name])


func _test_cycling_changes_your_ninja() -> void:
	var before := _kurogane.character_def.display_name
	await _cycle(_kurogane.slot, 1)

	_check(_kurogane.character_def.display_name != before,
		"pushing right picks the next ninja (%s -> %s)"
			% [before, _kurogane.character_def.display_name])
	_check(_kurogane.max_health == _kurogane.character_def.get_max_health(),
		"and the swap actually re-derives their stats (%.0f health)" % _kurogane.max_health)


func _test_cycling_wraps_both_ways() -> void:
	var start := _kurogane.slot.character_index
	for i in CharacterRoster.size():
		await _cycle(_kurogane.slot, 1)
	_check(_kurogane.slot.character_index == start,
		"cycling all the way round comes home (%d)" % _kurogane.slot.character_index)

	await _cycle(_kurogane.slot, -1)
	_check(_kurogane.slot.character_index != start, "and it cycles the other way too")
	await _cycle(_kurogane.slot, 1)


func _test_locking_in_stops_you_cycling() -> void:
	await _ready_up(_kurogane.slot)
	_check(_kurogane.slot.is_ready, "the jump button locks a choice in")

	var locked := _kurogane.slot.character_index
	await _cycle(_kurogane.slot, 1)
	_check(_kurogane.slot.character_index == locked,
		"a locked-in player cannot keep cycling")

	await _ready_up(_kurogane.slot)
	_check(not _kurogane.slot.is_ready, "and can change their mind")


# --- Starting a match ---

func _test_one_player_waits() -> void:
	await _ready_up(_kurogane.slot)
	_null.slot.is_ready = false
	match_manager.refresh_readiness()
	await _ticks(6)
	_check(match_manager.phase == MatchManager.Phase.WAITING,
		"one ready player is not a match (%s)" % match_manager.phase_name())


## Somebody still deciding should never be dropped into a countdown.
func _test_nobody_starts_until_everyone_is_ready() -> void:
	await _ready_up(_null.slot)
	await _ticks(4)
	_check(match_manager.phase == MatchManager.Phase.COUNTDOWN,
		"the countdown starts once everyone is ready (%s)" % match_manager.phase_name())


func _test_a_late_join_sends_it_back_to_select() -> void:
	_jinsoku = await _join(2)
	await _ticks(4)
	_check(match_manager.phase == MatchManager.Phase.WAITING,
		"a late join puts everyone back to choosing (%s)" % match_manager.phase_name())

	await _ready_up(_jinsoku.slot)
	await _ticks(4)
	_check(match_manager.phase == MatchManager.Phase.COUNTDOWN,
		"and it resumes once they are ready too (%s)" % match_manager.phase_name())


func _test_the_countdown_becomes_a_fight() -> void:
	for fighter: Fighter in [_kurogane, _null, _jinsoku]:
		fighter.slot.is_ready = true
	match_manager.refresh_readiness()
	for i in 120:
		await get_tree().physics_frame
		if match_manager.phase == MatchManager.Phase.FIGHTING:
			break
	_check(match_manager.phase == MatchManager.Phase.FIGHTING,
		"the countdown becomes a fight (%s)" % match_manager.phase_name())
	for fighter: Fighter in [_kurogane, _null, _jinsoku]:
		_check(match_manager.get_stocks(fighter.slot.index) == match_manager.stocks_per_player,
			"%s starts on a full set of stocks" % fighter.character_def.display_name)


# --- Stocks ---

## Knockouts before the bell are free, so warming up cannot cost anyone a match.
func _test_warm_up_knockouts_are_free() -> void:
	match_manager.auto_start = false
	match_manager._set_phase(MatchManager.Phase.WAITING)
	var before := match_manager.get_stocks(_null.slot.index)

	await _knock_out(_null)
	await _ticks(6)

	_check(match_manager.get_stocks(_null.slot.index) == before,
		"a knockout during warm-up costs nothing (%d)" % match_manager.get_stocks(_null.slot.index))
	_check(_null.health > 0.0, "and the fighter is put straight back on their feet")


func _test_a_knockout_costs_a_stock() -> void:
	match_manager._set_phase(MatchManager.Phase.FIGHTING)
	var before := match_manager.get_stocks(_null.slot.index)

	await _knock_out(_null)
	await _ticks(6)

	_check(match_manager.get_stocks(_null.slot.index) == before - 1,
		"a knockout costs a stock (%d -> %d)"
			% [before, match_manager.get_stocks(_null.slot.index)])
	_check(_null.health > 0.0, "and the fighter comes back (%.0f health)" % _null.health)
	_check(not _null.is_eliminated, "with stocks left, nobody is eliminated")


## Otherwise whoever is standing on the spawn point takes the next stock too.
func _test_respawning_is_briefly_invulnerable() -> void:
	_check(_null.is_invulnerable(), "a respawned fighter is briefly invulnerable")


# --- Elimination and victory ---

func _test_running_out_eliminates() -> void:
	_eliminations.clear()
	await _knock_out(_null)
	await _ticks(8)

	_check(match_manager.get_stocks(_null.slot.index) == 0, "the last stock is spent")
	_check(_null.is_eliminated, "spending the last stock eliminates the fighter")
	_check(not _null.visible, "an eliminated fighter is taken off the field")
	_check(_eliminations.has(_null.slot.get_label()),
		"the elimination is announced (%s)" % str(_eliminations))


func _test_the_camera_drops_eliminated_fighters() -> void:
	# With one fighter hidden, framing must be decided by the two still in it.
	_kurogane.global_position = Vector3(-4, 0.3, 13)
	_jinsoku.global_position = Vector3(4, 0.3, 13)
	_null.global_position = Vector3(0, 0.3, -14)
	await _ticks(120)

	var focus := _camera.get_focus()
	var midpoint := (_kurogane.global_position + _jinsoku.global_position) * 0.5
	_check(focus.distance_to(midpoint) < 3.0,
		"the camera frames the living, not the eliminated (off by %.1f)"
			% focus.distance_to(midpoint))


func _test_last_standing_wins() -> void:
	_ended = 0
	_last_winner = null
	while match_manager.get_stocks(_jinsoku.slot.index) > 0:
		await _knock_out(_jinsoku)
		await _ticks(8)

	_check(_ended == 1, "the match ends once (%d)" % _ended)
	_check(match_manager.phase == MatchManager.Phase.VICTORY,
		"the match reaches victory (%s)" % match_manager.phase_name())
	_check(_last_winner == _kurogane.slot,
		"the last fighter standing wins (%s)"
			% (_last_winner.get_label() if _last_winner != null else "nobody"))


func _test_victory_resets_for_a_rematch() -> void:
	for i in 180:
		await get_tree().physics_frame
		if match_manager.phase != MatchManager.Phase.VICTORY:
			break

	_check(match_manager.phase != MatchManager.Phase.VICTORY,
		"victory does not last forever (%s)" % match_manager.phase_name())
	for fighter: Fighter in [_kurogane, _null, _jinsoku]:
		_check(not fighter.is_eliminated,
			"%s is back for the rematch" % fighter.character_def.display_name)
		_check(fighter.visible, "%s is visible again" % fighter.character_def.display_name)
		_check(match_manager.get_stocks(fighter.slot.index) == match_manager.stocks_per_player,
			"%s has a full set of stocks again" % fighter.character_def.display_name)


# --- Local helpers ---

## One bumper tap is one roster step. Cycling is on the bumpers rather than the
## stick precisely so that walking around before the bell does not change who
## you are playing.
func _cycle(slot: PlayerSlot, direction: int) -> void:
	var source := slot.source as ScriptedInputSource
	var action := InputFrame.Action.LAUNCHER if direction > 0 else InputFrame.Action.BLOCK
	source.hold(action, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(action, false)
	await _ticks(3)


func _ready_up(slot: PlayerSlot) -> void:
	var source := slot.source as ScriptedInputSource
	source.hold(InputFrame.Action.JUMP, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(InputFrame.Action.JUMP, false)
	await _ticks(3)

## Applies a lethal hit, which is how a fighter reports a knockout.
func _knock_out(fighter: Fighter) -> void:
	fighter.grant_invulnerability(0)
	fighter._invulnerable = 0
	var result := HitResult.new()
	result.attacker = null
	result.damage = fighter.max_health * 2.0
	result.knockback = Vector3.ZERO
	result.hitstun_ticks = 1
	result.hitstop_ticks = 0
	result.position = fighter.global_position
	fighter.take_hit(result)
	await get_tree().physics_frame
