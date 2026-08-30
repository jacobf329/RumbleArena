## Headless verification of the AI seats.
##
## The thing worth testing about a bot is not that it wins -- it is that it is
## not allowed to cheat. Every check here goes through the same InputFrame a
## human fills, so if the AI ever reached past the input layer to move or hit
## somebody directly, these would keep passing while the bot quietly stopped
## being a player. The first section pins that down explicitly.
extends TestHarness

var _human: Fighter


func _init() -> void:
	test_name = "M5 bot test"


func _run() -> void:
	_section("A bot is just another input source")
	await _test_a_bot_takes_a_seat()
	await _test_a_bot_drives_its_fighter_through_an_input_frame()
	await _test_a_bot_never_shares_a_device_with_a_player()
	await _test_bots_are_ready_the_moment_they_sit_down()

	_section("Playing the game")
	await _test_a_bot_walks_toward_its_opponent()
	await _test_a_bot_throws_hands_in_range()
	await _test_a_bot_leaves_the_arena_alone_when_it_is_the_only_one_there()
	await _test_a_bot_stops_giving_orders_while_it_is_being_hit()
	await _test_a_bot_grabs_a_guard()

	_section("Getting around the arena")
	await _test_a_bot_gets_round_an_obstacle()
	await _test_a_bot_goes_where_the_fight_is()
	await _test_a_bot_falls_for_an_afterimage()

	_section("Leaving the bench")
	await _test_a_bot_can_be_removed()
	await _test_removing_a_bot_frees_its_fighter()
	await _test_a_removed_bot_stops_counting_toward_the_match()
	await _test_removing_never_takes_a_human_seat()
	await _test_the_pad_cycles_the_whole_bench()

	_section("Match flow with bots")
	await _test_a_bot_bench_starts_a_match()
	await _test_a_rematch_does_not_strand_the_bots()


# --- A bot is just another input source ---

func _test_a_bot_takes_a_seat() -> void:
	_clear_seats()
	_human = await _join(0)
	var slot := PlayerManager.add_bot(0.6)
	await get_tree().physics_frame

	_check(slot != null, "adding a bot fills a free seat")
	_check(slot.is_bot(), "the seat reports itself as a bot")
	_check(slot.source is InputSource, "a bot is an InputSource like any other")
	_check(slot.fighter != null, "the bot spawned a fighter through the normal join path")
	_check(slot.get_label() == "CPU2", "the HUD labels the seat CPU, not P")
	_check(PlayerManager.get_bot_count() == 1, "the manager counts one bot")


## The whole point of the M1 input rule. A bot presses buttons; it does not
## touch the fighter. If this ever fails, the AI has grown a back door.
func _test_a_bot_drives_its_fighter_through_an_input_frame() -> void:
	var bot := _bot(0)
	var fighter := _bot_fighter(0)
	# Face the bot at the human so it has a reason to move.
	fighter.global_position = _human.global_position + Vector3(6.0, 0.0, 0.0)
	await _ticks(20)

	var frame := fighter.slot.get_frame()
	_check(frame != null, "the bot's seat exposes an InputFrame")
	_check(frame.move.length() > 0.1, "the bot's intent shows up as stick movement")
	_check(bot.fighter == fighter, "the bot can see the body it is driving")


func _test_a_bot_never_shares_a_device_with_a_player() -> void:
	var ids: Array[int] = []
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		ids.append(slot.source.get_device_id())
	var unique := {}
	for id in ids:
		unique[id] = true
	_check(unique.size() == ids.size(), "every seated source has its own device id")
	_check(_bot(0).get_device_id() < InputSource.KEYBOARD_DEVICE,
		"bot device ids stay clear of the keyboard and real pads")


## A bot has no way to press the lock-in button, so a bot seat that started
## un-ready would stall every countdown forever.
func _test_bots_are_ready_the_moment_they_sit_down() -> void:
	_check(_bot_slot(0).is_ready, "a new bot is already locked in")


# --- Playing the game ---

func _test_a_bot_walks_toward_its_opponent() -> void:
	var fighter := _bot_fighter(0)
	fighter.global_position = _human.global_position + Vector3(7.0, 0.0, 0.0)
	await get_tree().physics_frame
	var before := fighter.global_position.distance_to(_human.global_position)
	await _ticks(60)
	var after := fighter.global_position.distance_to(_human.global_position)
	_check(after < before - 1.0, "the bot closes the distance (%.1f m -> %.1f m)" % [before, after])


func _test_a_bot_throws_hands_in_range() -> void:
	var fighter := _bot_fighter(0)
	fighter.global_position = _human.global_position + Vector3(1.2, 0.0, 0.0)
	await get_tree().physics_frame

	var attacked := false
	for i in 180:
		await get_tree().physics_frame
		if fighter.get_state_id() == FighterState.ATTACK:
			attacked = true
			break
	_check(attacked, "the bot attacks once it is in range")

	var health_before := _human.health
	await _ticks(240)
	_check(_human.health < health_before, "the bot's attacks actually land (%.1f -> %.1f)"
		% [health_before, _human.health])


## An empty arena is not a reason to flail. With nobody to fight the bot should
## produce no intent at all.
func _test_a_bot_leaves_the_arena_alone_when_it_is_the_only_one_there() -> void:
	_human.hide()
	_human.is_eliminated = true
	await _ticks(90)
	var frame := _bot_slot(0).get_frame()
	_check(frame.move == Vector2.ZERO, "with no living target the bot stands still")

	_human.is_eliminated = false
	_human.show()
	_human.health = _human.max_health
	await _ticks(4)


func _test_a_bot_stops_giving_orders_while_it_is_being_hit() -> void:
	var fighter := _bot_fighter(0)
	var result := HitResult.new()
	result.attacker = _human
	result.damage = 1.0
	result.knockback = Vector3(2.0, 0.0, 0.0)
	result.hitstun_ticks = 40
	result.position = fighter.global_position
	fighter.take_hit(result)
	await _ticks(6)

	_check(fighter.get_state_id() == FighterState.HITSTUN, "the bot is in hitstun")
	_check(_bot_slot(0).get_frame().move == Vector2.ZERO,
		"a bot in hitstun issues no movement -- it eats the combo like anyone else")
	await _ticks(60)


## Grab beats block. A bot that mashed strikes into a guard would be teaching
## players the wrong lesson about the rock-paper-scissors.
##
## The check is on the button, not on the outcome: a blocked strike can push the
## guard into hitstun too, so "the opponent got stunned" would pass for the
## wrong reason. What the AI is claimed to do is press grab at a guard, and that
## is exactly what an InputFrame can be asked.
func _test_a_bot_grabs_a_guard() -> void:
	var fighter := _bot_fighter(0)
	var frame := _bot_slot(0).get_frame()
	fighter.health = fighter.max_health
	_human.health = _human.max_health

	var grabs_at_a_guard := 0
	var strikes_at_a_guard := 0
	for i in 600:
		# Pinned in range and topped up, so the bot is choosing between options
		# rather than walking, recovering, or running out of guard to attack.
		fighter.global_position = _human.global_position + Vector3(1.1, 0.0, 0.0)
		_human.stamina = _human.max_stamina
		_source(_human).hold(InputFrame.Action.BLOCK, true)
		await get_tree().physics_frame
		if _human.get_state_id() != FighterState.BLOCK:
			continue
		if frame.is_just_pressed(InputFrame.Action.GRAB):
			grabs_at_a_guard += 1
		if frame.is_just_pressed(InputFrame.Action.LIGHT):
			strikes_at_a_guard += 1

	_source(_human).hold(InputFrame.Action.BLOCK, false)
	_check(grabs_at_a_guard > 0,
		"the bot answers a guard with a grab (%d grabs, %d strikes)"
			% [grabs_at_a_guard, strikes_at_a_guard])
	await _ticks(60)


# --- Getting around the arena ---

## Bots have no navigation mesh, so an arena with a pillar in it is the whole
## test: walking straight at somebody works until something is in the way, and
## then a bot with no answer stands there pushing into concrete for the rest of
## the match. (Before this existed, four bots spent up to a fifth of a match
## wedged on the ramps.)
func _test_a_bot_gets_round_an_obstacle() -> void:
	var fighter := _bot_fighter(0)
	# PillarA in the proving ground is 5 m tall and sits at (7, -7): too tall to
	# jump, so the only way through is around.
	_human.global_position = Vector3(7.0, 0.0, -4.2)
	fighter.global_position = Vector3(7.0, 0.0, -9.8)
	_source(_human).move = Vector2.ZERO
	await _ticks(4)

	var start := fighter.global_position.distance_to(_human.global_position)
	var closest := start
	for i in 240:
		await get_tree().physics_frame
		# Pin the target so this measures the bot's route, not a chase.
		_human.global_position = Vector3(7.0, 0.0, -4.2)
		closest = minf(closest, fighter.global_position.distance_to(_human.global_position))

	_check(closest < 2.5,
		"the bot routes around a pillar rather than pushing into it (%.1f m -> %.1f m)"
			% [start, closest])


## Nearest-target picking splits four bots into two duels in opposite corners,
## and a single shared camera cannot frame that. A bot should be drawn to the
## scrum, the way a player is.
func _test_a_bot_goes_where_the_fight_is() -> void:
	_clear_seats()
	var lone := await _join(0)
	var scrum_a := await _join(1)
	var scrum_b := await _join(2)
	var slot := PlayerManager.add_bot(0.5)
	await _ticks(3)
	var bot := _bot(0)
	var fighter := slot.fighter as Fighter

	fighter.global_position = Vector3.ZERO
	# The loner is closer; the pair are further out but they are the fight.
	lone.global_position = Vector3(-6.0, 0.0, 0.0)
	scrum_a.global_position = Vector3(9.0, 0.0, 1.0)
	scrum_b.global_position = Vector3(9.0, 0.0, -1.0)
	await _ticks(2)

	var picked := bot._pick_target()
	_check(picked != lone, "the bot does not pair off with the nearest straggler")
	_check(picked == scrum_a or picked == scrum_b, "it heads for where everyone else is")

	# With the pull off it should make the opposite, obviously-worse choice --
	# otherwise this test would pass whether or not the pull did anything.
	bot.crowd_pull = 0.0
	_check(bot._pick_target() == lone, "with the pull off it takes the nearest instead")
	bot.crowd_pull = BotInputSource.DEFAULT_CROWD_PULL


## A decoy that only fooled humans would be half a power. The bot has no eyes
## to deceive, so the deception has to exist where it does its deciding: a
## decoy is a legitimate thing to be walking at, and popping one is the price.
func _test_a_bot_falls_for_an_afterimage() -> void:
	_clear_seats()
	_human = await _join(0)
	var slot := PlayerManager.add_bot(0.5)
	await _ticks(3)
	var bot := _bot(0)
	var fighter := _bot_fighter(0)

	# Human well away; a decoy right next to the bot.
	_human.global_position = Vector3(-10.0, 0.3, 10.0)
	fighter.global_position = Vector3(6.0, 0.3, 6.0)
	await _ticks(2)

	var decoy: Afterimage = preload("res://scenes/effects/afterimage.tscn").instantiate()
	# Long enough that it cannot expire on its own inside this test: an
	# afterimage that simply ran out of time would leave every check below
	# passing without the bot having done anything at all.
	decoy.lifetime_ticks = 900
	_main.get_node("Arena").interactable_root().add_child(decoy)
	decoy.global_position = Vector3(8.0, 0.3, 6.0)
	decoy.setup(_human, Color.CYAN)
	await _ticks(4)

	_check(bot._pick_target() == decoy,
		"the bot picks the decoy over a distant real fighter")

	# And swinging at it pops it, which is the whole cost. Put it in arm's reach
	# and hold it there: how long the bot takes to WALK somewhere depends on its
	# strafing rolls and on whatever scenery it detours around, and this check is
	# about what it does when it arrives, not how long it takes to get there.
	var health_before := fighter.health
	var popped := false
	for i in 600:
		if is_instance_valid(decoy):
			decoy.global_position = fighter.global_position \
				+ fighter.get_facing_direction() * 1.1
		await get_tree().physics_frame
		if not is_instance_valid(decoy):
			popped = true
			break
	_check(popped, "it walks up and pops it")
	_check(fighter.health < health_before,
		"and eats the burst for doing so (%.1f -> %.1f)" % [health_before, fighter.health])
	await _ticks(30)


# --- Leaving the bench ---

func _test_a_bot_can_be_removed() -> void:
	_clear_seats()
	_human = await _join(0)
	PlayerManager.add_bot()
	await _ticks(2)

	var removed := PlayerManager.remove_bot()
	await _ticks(2)
	_check(removed != null, "removing a bot reports which seat it left")
	_check(PlayerManager.get_bot_count() == 0, "no bots remain")
	_check(not removed.is_active(), "the seat is free again")
	_check(PlayerManager.remove_bot() == null, "removing from an empty bench is a no-op")


func _test_removing_a_bot_frees_its_fighter() -> void:
	PlayerManager.add_bot()
	await _ticks(2)
	var fighter := _bot_fighter(0)
	var slot := _bot_slot(0)
	PlayerManager.remove_bot()
	await _ticks(4)

	_check(not is_instance_valid(fighter), "the bot's fighter is gone from the arena")
	_check(slot.fighter == null, "the seat is not holding a dangling fighter")
	_check(not _camera_frames(fighter), "the camera stopped framing it")


## Otherwise pulling a bot out mid-match would leave a ghost that the
## last-ninja-standing check waits on forever.
func _test_a_removed_bot_stops_counting_toward_the_match() -> void:
	PlayerManager.add_bot()
	await _ticks(2)
	var index := _bot_slot(0).index
	_check(match_manager.get_stocks(index) > 0, "the bot is registered with stocks")
	PlayerManager.remove_bot()
	await _ticks(4)
	_check(match_manager.get_stocks(index) == 0, "the removed seat no longer holds stocks")
	for slot: PlayerSlot in match_manager.get_living_slots():
		_check(slot.index != index, "the removed seat is not counted as still living")


func _test_removing_never_takes_a_human_seat() -> void:
	_check(PlayerManager.remove_bot() == null, "with only humans seated, remove is a no-op")
	_check(_human.slot.is_active(), "the human keeps their seat")


## One spare button on the pad, so filling the arena has to wrap back round to
## emptying it rather than dead-ending at three CPUs.
func _test_the_pad_cycles_the_whole_bench() -> void:
	_clear_seats()
	_human = await _join(0)
	while PlayerManager.get_free_slot() != null:
		PlayerManager.add_bot()
	await _ticks(3)
	_check(PlayerManager.get_bot_count() == 3, "the bench fills the remaining seats")

	var cleared := PlayerManager.clear_bots()
	await _ticks(3)
	_check(cleared == 3, "clearing empties the whole bench in one press")
	_check(PlayerManager.get_active_count() == 1, "only the human is left")
	for slot: PlayerSlot in PlayerManager.slots:
		if slot.index != 0:
			_check(slot.fighter == null, "seat %d left no fighter behind" % (slot.index + 1))


# --- Match flow with bots ---

## The reason bots exist: one person on a couch should be able to see whether
## four-way chaos holds up.
func _test_a_bot_bench_starts_a_match() -> void:
	_clear_seats()
	match_manager.auto_start = true
	match_manager.countdown_seconds = 0.3
	match_manager.stocks_per_player = 2
	_human = await _join(0)
	_human.slot.is_ready = true
	match_manager.refresh_readiness()

	PlayerManager.add_bot()
	PlayerManager.add_bot()
	PlayerManager.add_bot()
	await _ticks(4)

	_check(PlayerManager.get_active_count() == 4, "one human plus three bots fills the arena")
	_check(match_manager.phase == MatchManager.Phase.COUNTDOWN,
		"the bench does not hold up the bell")
	await _ticks(40)
	_check(match_manager.phase == MatchManager.Phase.FIGHTING, "the countdown became a fight")

	var skills: Array[float] = []
	for bot in PlayerManager.get_bot_sources():
		skills.append(bot.skill)
	_check(skills.size() == 3 and skills.max() > skills.min(),
		"the bench is a ladder, not three copies of the same opponent")

	# Mid-fight a new bot would arrive with a full set of stocks against players
	# who have already spent theirs.
	PlayerManager.remove_bot()
	await _ticks(3)
	_main._add_bot()
	await _ticks(3)
	_check(PlayerManager.get_bot_count() == 2, "a bot cannot join a fight already in progress")


## A rematch un-readies the humans so they can change ninja. Doing that to a
## bot would leave a seat nobody could ever ready again.
func _test_a_rematch_does_not_strand_the_bots() -> void:
	match_manager.victory_seconds = 0.2
	# End it the blunt way: leave one fighter alive.
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		if slot.index == 0:
			continue
		var fighter := slot.fighter as Fighter
		for i in match_manager.stocks_per_player:
			fighter.defeated.emit()
			await get_tree().physics_frame
	await _ticks(4)
	_check(match_manager.phase == MatchManager.Phase.VICTORY, "the match ended")

	await _ticks(40)
	_check(match_manager.phase != MatchManager.Phase.VICTORY, "victory rolled over")
	var all_ready := true
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		if slot.is_bot() and not slot.is_ready:
			all_ready = false
	_check(all_ready, "every bot is still ready for the rematch")
	_check(not PlayerManager.slots[0].is_ready, "the human is un-readied so they can re-pick")


# --- Helpers ---

func _bot_slot(nth: int) -> PlayerSlot:
	var found := 0
	for slot: PlayerSlot in PlayerManager.slots:
		if slot.is_bot():
			if found == nth:
				return slot
			found += 1
	return null


func _bot(nth: int) -> BotInputSource:
	var slot := _bot_slot(nth)
	return slot.source as BotInputSource if slot != null else null


func _bot_fighter(nth: int) -> Fighter:
	var slot := _bot_slot(nth)
	return slot.fighter as Fighter if slot != null else null


func _camera_frames(fighter: Fighter) -> bool:
	for target in _camera._targets:
		if target == fighter:
			return true
	return false


## Empties every seat between sections, so one section's bench does not decide
## what the next one is testing.
func _clear_seats() -> void:
	for slot: PlayerSlot in PlayerManager.slots:
		if not slot.is_active():
			continue
		slot.source = null
		slot.is_ready = false
		# The arena's own teardown does the rest, so a test seat is emptied by
		# the same path the F3 key uses rather than by a test-only shortcut.
		PlayerManager.player_left.emit(slot)
	match_manager.auto_start = false
	await _ticks(3)
