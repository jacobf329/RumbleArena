## Headless verification of the M2 combat core.
##
## Combat is measured the way a player experiences it: press a button, watch
## what lands. Frame counts are compared against the frame data rather than
## hardcoded, so retuning a move updates its own test.
extends TestHarness

## Open floor with no arena geometry in it, so a knockback measures knockback
## rather than how quickly the victim finds a ledge.
const STAGE := Vector3(-9, 0.3, 14)
const GAP := 1.3
## Ticks between taps that counts as mashing: too early to score, but far enough
## apart that the button genuinely releases in between.
const MASH_DELAY := 3

var _hits: Array[HitResult] = []
## Physics tick each hit landed on, so a cancel can be told apart from simply
## waiting out the recovery and starting the move fresh.
var _hit_ticks: Array[int] = []
var _defeats := 0
var _fighters: Array[Fighter] = []


func _init() -> void:
	test_name = "M2 combat test"


func _run() -> void:
	var kurogane := await _join(0)   # STR 5 / SPD 2 -- heavy and slow
	var null_fighter := await _join(1)   # STR 1 / SPD 4 -- light and quick
	var jinsoku := await _join(2)    # SPD 5 -- fastest attacks
	var yamabuki := await _join(3)   # the usual victim

	_fighters = [kurogane, null_fighter, jinsoku, yamabuki]
	for fighter: Fighter in _fighters:
		fighter.damaged.connect(func(result: HitResult) -> void:
			_hits.append(result)
			_hit_ticks.append(Engine.get_physics_frames()))
	yamabuki.defeated.connect(func() -> void: _defeats += 1)

	await _ticks(30)

	_section("Frame data")
	await _test_startup_is_real(kurogane, yamabuki)
	await _test_speed_stat_changes_startup(kurogane, jinsoku, yamabuki)

	_section("Hits")
	await _test_light_deals_its_damage(kurogane, yamabuki)
	await _test_power_builds_on_connect(kurogane, yamabuki)
	await _test_strength_and_toughness_are_asymmetric(kurogane, null_fighter)

	_section("Chains and confirms")
	await _test_light_chain(kurogane, yamabuki)
	await _test_whiffed_confirm_cannot_cancel(kurogane, yamabuki)
	await _test_connected_confirm_cancels(kurogane, yamabuki)

	_section("Reactions")
	await _test_launcher_sends_upward(kurogane, yamabuki)
	await _test_hitstun_removes_control(kurogane, yamabuki)
	await _test_hitstop_freezes_both(kurogane, yamabuki)
	await _test_knockdown_and_tech(kurogane, yamabuki)
	await _test_wall_splat_extends_stun(kurogane, yamabuki)

	_section("Defence")
	await _test_block_reduces_and_holds(kurogane, yamabuki)
	await _test_block_only_covers_the_front(kurogane, yamabuki)
	await _test_invulnerability_denies_hits(kurogane, yamabuki)
	await _test_dodge_grants_invulnerability(yamabuki)
	await _test_stamina_gates_dodging(yamabuki)

	_section("Fireball and grab")
	await _test_finisher_launches_a_fireball(kurogane, yamabuki)
	await _test_fireball_needs_power(kurogane, yamabuki)
	await _test_grab_beats_block(kurogane, yamabuki)
	await _test_whiffed_grab_is_punishable(kurogane)

	_section("Rhythm")
	_test_animation_data_is_sane(kurogane)
	await _test_mashing_earns_nothing(kurogane, yamabuki)
	await _test_timing_the_cancel_pays(kurogane, yamabuki)

	_section("Feedback and flow")
	await _test_hit_shakes_the_camera(kurogane, yamabuki)
	await _test_defeat_at_zero_health(kurogane, yamabuki)


# --- Frame data ---

func _test_startup_is_real(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	var expected := _scaled_startup(attacker, attacker.move_set.light(0))
	var measured := await _ticks_until_hit(attacker, victim, InputFrame.Action.LIGHT)

	_check(measured >= expected,
		"the hitbox is not live during startup (hit on tick %d, startup %d)"
			% [measured, expected])
	_check(measured >= 0 and measured <= expected + 3,
		"the hitbox goes live right after startup (tick %d, startup %d)"
			% [measured, expected])


## The clearest expression of pillar P1 in combat: the same authored move is a
## different move in a slow character's hands.
func _test_speed_stat_changes_startup(slow: Fighter, fast: Fighter, victim: Fighter) -> void:
	await _stage(slow, victim)
	var slow_ticks := await _ticks_until_hit(slow, victim, InputFrame.Action.HEAVY)
	await _stage(fast, victim)
	var fast_ticks := await _ticks_until_hit(fast, victim, InputFrame.Action.HEAVY)

	_check(slow_ticks >= 0 and fast_ticks >= 0,
		"both heavies connect for the startup comparison (%d, %d)" % [slow_ticks, fast_ticks])
	_check(slow_ticks > fast_ticks and fast_ticks >= 0,
		"Kurogane's heavy (SPD 2) starts up slower than Jinsoku's (SPD 5): %d vs %d ticks"
			% [slow_ticks, fast_ticks])


# --- Hits ---

func _test_light_deals_its_damage(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	var full := victim.health
	var landed := await _ticks_until_hit(attacker, victim, InputFrame.Action.LIGHT)

	_check(landed >= 0, "a light attack connects")
	if landed < 0:
		return

	var expected: float = CombatMath.damage(attacker.move_set.light(0), attacker.character_def)
	_check(absf((full - victim.health) - expected) < 0.01,
		"damage matches the formula (%.1f dealt, expected %.1f)"
			% [full - victim.health, expected])


func _test_power_builds_on_connect(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	attacker.power = 0.0
	await _ticks_until_hit(attacker, victim, InputFrame.Action.LIGHT)

	_check(absf(attacker.power - attacker.move_set.light(0).power_gain) < 0.01,
		"landing a hit builds power (%.1f)" % attacker.power)


## Damage answers to the attacker's STRENGTH alone; knockback is the contest
## between STRENGTH and TOUGHNESS. Both directions of the same matchup.
func _test_strength_and_toughness_are_asymmetric(bruiser: Fighter, hacker: Fighter) -> void:
	var heavy := bruiser.move_set.heavy
	var bruiser_damage: float = CombatMath.damage(heavy, bruiser.character_def)
	var hacker_damage: float = CombatMath.damage(heavy, hacker.character_def)
	_check(bruiser_damage > hacker_damage * 1.4,
		"Kurogane's heavy hits far harder than Null's (%.1f vs %.1f)"
			% [bruiser_damage, hacker_damage])

	var out: float = CombatMath.knockback_speed(heavy, bruiser.character_def, hacker.character_def)
	var back: float = CombatMath.knockback_speed(heavy, hacker.character_def, bruiser.character_def)
	_check(out > back * 1.8,
		"Kurogane sends Null much further than the reverse (%.1f vs %.1f)" % [out, back])


# --- Chains and confirms ---

## Both fighters are pinned so this measures the cancel logic and nothing else;
## without pinning, knockback would decide whether link two lands.
func _test_light_chain(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	attacker.power = 0.0  # no meter, so the finisher's fireball stays out of it
	var source := _source(attacker)

	for link in 3:
		_tap(source, InputFrame.Action.LIGHT)
		await _pinned_until_hits(link + 1, attacker, victim, 80)
		await _pinned_ticks(2, attacker, victim)
	await _pinned_ticks(40, attacker, victim)

	var names: Array = _hits.map(func(r: HitResult) -> String:
		return r.attack.display_name if r.attack != null else "<projectile>")
	_check(_hits.size() == 3, "the light chain lands three distinct hits (got %d: %s)"
		% [_hits.size(), ", ".join(names)])
	if _hits.size() != 3:
		return
	_check(names == ["Jab", "Cross", "Roundhouse"],
		"the chain runs jab into cross into roundhouse (%s)" % ", ".join(names))
	_check(_hits[2].damage > _hits[0].damage,
		"the chain finisher hits harder than the opener (%.1f vs %.1f)"
			% [_hits[2].damage, _hits[0].damage])
	_check(attacker.cancel_count == 2,
		"the follow-ups arrived by cancelling, not by waiting out recovery (%d cancels)"
			% attacker.cancel_count)


## A whiffed heavy is meant to cost the full recovery. If the confirm cancelled
## anyway, committing to a heavy would be free.
func _test_whiffed_confirm_cannot_cancel(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim, 6.0)  # far out of range: the heavy will whiff
	var source := _source(attacker)

	_tap(source, InputFrame.Action.HEAVY)
	await _ticks(20)
	# Put the victim back in range and ask for the follow-up.
	victim.global_position = attacker.global_position + attacker.get_facing_direction() * GAP
	_tap(source, InputFrame.Action.LAUNCHER)
	await _pinned_ticks(90, attacker, victim)

	_check(attacker.cancel_count == 0,
		"a whiffed heavy cannot be cancelled into a launcher (%d cancels)"
			% attacker.cancel_count)


func _test_connected_confirm_cancels(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	var source := _source(attacker)

	_tap(source, InputFrame.Action.HEAVY)
	await _pinned_ticks(18, attacker, victim)
	_tap(source, InputFrame.Action.LAUNCHER)
	await _pinned_ticks(70, attacker, victim)

	_check(_hits.size() == 2,
		"a connected heavy confirms into the launcher (got %d hits)" % _hits.size())
	if _hits.size() != 2:
		return
	_check(_hits[1].attack.display_name == "Uppercut",
		"the confirm is the launcher (%s)" % _hits[1].attack.display_name)

	_check(attacker.cancel_count == 1,
		"the confirm really cancels rather than waiting out recovery (%d cancels)"
			% attacker.cancel_count)


# --- Reactions ---

func _test_launcher_sends_upward(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	await _ticks_until_hit(attacker, victim, InputFrame.Action.LAUNCHER)

	_check(not _hits.is_empty(), "the launcher connects")
	if _hits.is_empty():
		return
	var knockback := _hits[0].knockback
	_check(knockback.y > knockback.length() * 0.9,
		"the launcher sends the victim almost straight up (y %.1f of %.1f)"
			% [knockback.y, knockback.length()])


func _test_hitstun_removes_control(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	await _ticks_until_hit(attacker, victim, InputFrame.Action.LIGHT)

	_check(victim.get_state_id() == FighterState.HITSTUN,
		"being hit puts the victim in hitstun (state %s)" % victim.get_state_id())

	# Full stick and every button: none of it should give control back.
	var victim_source := _source(victim)
	victim_source.move = Vector2(1, 0)
	victim_source.hold(InputFrame.Action.JUMP, true)
	await _ticks(4)
	_check(victim.get_state_id() == FighterState.HITSTUN,
		"input does not break the victim out of hitstun")
	victim_source.move = Vector2.ZERO
	victim_source.release_all()


## With no animation to sell a hit, hitstop and knockback are where the impact
## actually comes from -- so it is worth asserting the freeze really happens.
func _test_hitstop_freezes_both(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	_tap(_source(attacker), InputFrame.Action.LIGHT)
	var landed := await _await_hit()
	_check(landed, "a hit lands for the hitstop check (%d attacks started, gap %.2f)"
		% [attacker.attacks_started,
			attacker.global_position.distance_to(victim.global_position)])
	if not landed:
		return

	await get_tree().physics_frame
	var attacker_at := attacker.global_position
	var victim_at := victim.global_position
	await _ticks(2)

	_check(attacker.global_position.distance_to(attacker_at) < 0.001,
		"the attacker is frozen during hitstop")
	_check(victim.global_position.distance_to(victim_at) < 0.001,
		"the victim is frozen during hitstop")

	await _ticks(30)
	_check(victim.global_position.distance_to(victim_at) > 0.1,
		"the victim moves again once hitstop ends")


func _test_knockdown_and_tech(attacker: Fighter, victim: Fighter) -> void:
	# Facing +X gives roughly 25 metres of clear floor. Anything shorter and the
	# victim splats into geometry, and a splat deliberately cancels knockdown.
	await _stage(attacker, victim, GAP, Vector3.RIGHT)
	await _ticks_until_hit(attacker, victim, InputFrame.Action.HEAVY)

	var downed := false
	for i in 140:
		await get_tree().physics_frame
		if victim.get_state_id() == FighterState.KNOCKDOWN:
			downed = true
			break
	_check(downed, "a heavy knocks the victim down")
	if not downed:
		return

	# Teching out early is the reward for reacting; it should also come with
	# invulnerability, or waking up would just feed the attacker.
	_tap(_source(victim), InputFrame.Action.DODGE)
	await _ticks(3)
	_check(victim.get_state_id() != FighterState.KNOCKDOWN,
		"teching gets the victim up early (state %s)" % victim.get_state_id())
	_check(victim.is_invulnerable(), "a tech comes with invulnerability")
	await _ticks(30)


func _test_wall_splat_extends_stun(attacker: Fighter, victim: Fighter) -> void:
	# Line the victim up against the west barrier and hit them into it.
	await _stage(attacker, victim)
	victim.global_position = Vector3(-15.0, 0.3, 10.0)
	attacker.global_position = Vector3(-13.5, 0.3, 10.0)
	attacker.snap_facing(Vector3.LEFT)
	await _ticks(10)
	_hits.clear()

	_tap(_source(attacker), InputFrame.Action.HEAVY)
	var landed := await _await_hit()
	_check(landed, "the heavy connects for the wall-splat check")
	if not landed:
		return

	var base_stun := _hits[0].hitstun_ticks
	var stunned_for := 0
	var knocked_down := false
	for i in 200:
		await get_tree().physics_frame
		var state: StringName = victim.get_state_id()
		if state == FighterState.HITSTUN:
			stunned_for += 1
		elif state == FighterState.KNOCKDOWN:
			knocked_down = true
			break
		elif stunned_for > 0:
			break

	_check(stunned_for > base_stun + 10,
		"being splatted into a wall extends the stun (%d ticks vs %d base)"
			% [stunned_for, base_stun])
	_check(not knocked_down,
		"a wall splat sets up a juggle rather than a knockdown")
	await _ticks(40)


# --- Defence ---

func _test_block_reduces_and_holds(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	var victim_source := _source(victim)
	victim_source.hold(InputFrame.Action.BLOCK, true)
	await _ticks(4)
	_check(victim.get_state_id() == FighterState.BLOCK, "holding block enters the block state")

	var stamina_before := victim.stamina
	_tap(_source(attacker), InputFrame.Action.HEAVY)
	var landed := await _await_hit(140)
	_check(landed, "the attack reaches a blocking victim")
	if landed:
		var unblocked: float = CombatMath.damage(attacker.move_set.heavy, attacker.character_def)
		_check(_hits[0].blocked, "the hit is registered as blocked")
		_check(_hits[0].damage < unblocked * 0.3,
			"blocking cuts the damage to chip (%.1f of %.1f)" % [_hits[0].damage, unblocked])
		_check(is_zero_approx(_hits[0].knockback.y) or victim.velocity.y <= 0.01,
			"a blocked hit shoves but never launches")
		await _ticks(3)
		_check(victim.stamina < stamina_before,
			"blocking a heavy costs stamina (%.1f -> %.1f)" % [stamina_before, victim.stamina])
		_check(victim.get_state_id() == FighterState.BLOCK,
			"the victim stays in guard rather than being put in hitstun")
	victim_source.release_all()
	await _ticks(20)


## If guard covered every angle, holding it would be strictly correct.
func _test_block_only_covers_the_front(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	# Both face -Z, with the attacker behind the victim's back.
	victim.snap_facing(Vector3.FORWARD)
	attacker.global_position = victim.global_position + Vector3(0, 0, GAP)
	attacker.snap_facing(Vector3.FORWARD)

	var victim_source := _source(victim)
	victim_source.hold(InputFrame.Action.BLOCK, true)
	await _ticks(4)

	_tap(_source(attacker), InputFrame.Action.LIGHT)
	var landed := await _await_hit(140)
	_check(landed, "the attack reaches a victim guarding the wrong way")
	if landed:
		_check(not _hits[0].blocked, "a hit from behind is not blocked")
	victim_source.release_all()
	await _ticks(20)


func _test_invulnerability_denies_hits(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	victim.grant_invulnerability(120)
	var health_before := victim.health

	_tap(_source(attacker), InputFrame.Action.LIGHT)
	await _pinned_ticks(60, attacker, victim)

	_check(is_equal_approx(victim.health, health_before),
		"an invulnerable fighter takes no damage")
	_check(_hits.is_empty(), "an invulnerable fighter registers no hit at all")


func _test_dodge_grants_invulnerability(fighter: Fighter) -> void:
	await _stage(fighter, fighter)
	fighter.stamina = fighter.max_stamina
	await _ticks(4)

	_tap(_source(fighter), InputFrame.Action.DODGE)
	await _ticks(2)
	_check(fighter.get_state_id() == FighterState.DASH, "dodge enters the dash state")
	_check(fighter.is_invulnerable(), "dodging grants invulnerability frames")
	await _ticks(60)


func _test_stamina_gates_dodging(fighter: Fighter) -> void:
	await _stage(fighter, fighter)
	fighter.stamina = fighter.max_stamina
	await _ticks(4)

	var before := fighter.stamina
	_tap(_source(fighter), InputFrame.Action.DODGE)
	await _ticks(3)
	_check(absf((before - fighter.stamina) - Fighter.DODGE_STAMINA) < 0.5,
		"a dodge costs stamina (%.1f spent)" % (before - fighter.stamina))

	fighter.stamina = 1.0
	await _ticks(80)  # past the dash cooldown, but stamina is what matters here
	fighter.stamina = 1.0
	_tap(_source(fighter), InputFrame.Action.DODGE)
	await _ticks(3)
	_check(fighter.get_state_id() != FighterState.DASH,
		"a dodge is refused without the stamina to pay for it")

	fighter.stamina = 1.0
	await _ticks(60)
	_check(fighter.stamina > 1.0, "stamina regenerates (%.1f)" % fighter.stamina)


# --- Fireball and grab ---

## Landing punch, punch, kick ends in a projectile, so the chain finisher is
## worth reaching rather than just the biggest of the three hits.
func _test_finisher_launches_a_fireball(attacker: Fighter, victim: Fighter) -> void:
	# Out of melee range on purpose: the chain still runs on whiff, so what is
	# measured is the finisher casting rather than any punch connecting.
	await _stage(attacker, victim, 5.0)
	attacker.power = attacker.max_power
	var before := attacker.power

	var seen := await _run_chain_and_count_fireballs(attacker, victim)

	_check(attacker.power < before, "casting the fireball spends power (%.0f -> %.0f)"
		% [before, attacker.power])
	_check(seen > 0, "the finisher puts a fireball into the world (%d seen)" % seen)
	await _pinned_ticks(40, attacker, victim)


func _test_fireball_needs_power(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim, 5.0)
	attacker.power = 0.0

	var seen := await _run_chain_and_count_fireballs(attacker, victim)
	_check(seen == 0, "an empty meter casts nothing -- you just get the kick")
	await _pinned_ticks(30, attacker, victim)


## Grab beats block, block beats strike, strike beats grab. A guard that covered
## everything would make holding it strictly correct.
func _test_grab_beats_block(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	var victim_source := _source(victim)
	victim_source.hold(InputFrame.Action.BLOCK, true)
	await _ticks(5)
	_check(victim.get_state_id() == FighterState.BLOCK, "the victim is guarding")

	var health := victim.health
	_tap(_source(attacker), InputFrame.Action.GRAB)

	# Wait for the grab's own startup rather than assuming a tick count.
	var seized := false
	for i in 40:
		await get_tree().physics_frame
		if victim.get_state_id() == FighterState.HITSTUN:
			seized = true
			break
	_check(seized, "the grab takes hold through a guard (%s)" % victim.get_state_id())

	# Ride it out to the throw.
	var launched := false
	for i in 120:
		await get_tree().physics_frame
		if victim.velocity.length() > 6.0:
			launched = true
			break
	_check(launched, "the grab throws the victim")
	_check(victim.health < health, "the throw does damage (%.1f -> %.1f)"
		% [health, victim.health])
	victim_source.release_all()
	await _ticks(60)


func _test_whiffed_grab_is_punishable(attacker: Fighter) -> void:
	await _stage(attacker, attacker)
	var grab := attacker.move_set.grab
	_check(grab.ticks_recovery >= attacker.move_set.heavy.ticks_recovery,
		"a whiffed grab recovers no faster than a heavy (%d vs %d ticks)"
			% [grab.ticks_recovery, attacker.move_set.heavy.ticks_recovery])


## Runs the whole punch-punch-kick chain and reports the most fireballs alive at
## once. Pressing light only once would test the jab, not the finisher.
func _run_chain_and_count_fireballs(attacker: Fighter, victim: Fighter) -> int:
	var source := _source(attacker)
	var seen := 0
	for link in 3:
		_tap(source, InputFrame.Action.LIGHT)
		await _pinned_ticks(13, attacker, victim)
		seen = maxi(seen, _count_fireballs_in_scene())
	for i in 30:
		await get_tree().physics_frame
		seen = maxi(seen, _count_fireballs_in_scene())
	return seen


func _count_fireballs_in_scene() -> int:
	var count := 0
	for child in get_tree().current_scene.get_children():
		if child is Fireball:
			count += 1
	return count


# --- Rhythm ---

## Frame data owns gameplay timing and the clip is scaled to fit it, so the only
## way the two can disagree is if a move names a clip that is missing or puts its
## moment of contact outside the slice it actually plays.
func _test_animation_data_is_sane(fighter: Fighter) -> void:
	var library: AnimationLibrary = FighterVisual.ANIMATIONS
	var moves: Array[AttackDef] = [
		fighter.move_set.heavy, fighter.move_set.launcher,
		fighter.move_set.air_light, fighter.move_set.air_heavy,
	]
	moves.append_array(fighter.move_set.light_chain)

	for attack in moves:
		_check(attack.has_animation(), "%s names an animation" % attack.display_name)
		if not attack.has_animation():
			continue
		_check(library.has_animation(attack.animation),
			"%s's clip '%s' exists in the library" % [attack.display_name, attack.animation])
		_check(attack.animation_start <= attack.animation_impact
				and attack.animation_impact <= attack.animation_end,
			"%s's contact sits inside its slice (%.2f in %.2f..%.2f)" % [
				attack.display_name, attack.animation_impact,
				attack.animation_start, attack.animation_end])
		if library.has_animation(attack.animation):
			_check(attack.animation_end <= library.get_animation(attack.animation).length + 0.01,
				"%s's slice fits inside '%s'" % [attack.display_name, attack.animation])


## Mashing still combos -- it just earns nothing. That is the whole shape of the
## rhythm system: never punish the button masher, only reward the player who waits.
func _test_mashing_earns_nothing(attacker: Fighter, victim: Fighter) -> void:
	# Three ticks, not one: two taps a single tick apart give the button no
	# released frame in between, so the second never registers as a new press.
	# No human presses twice in 16ms either.
	var result := await _chain_with_delay(attacker, victim, MASH_DELAY)
	_check(result.y == 0, "mashing the follow-up earns no flow (flow %d)" % result.y)
	_check(result.x > 0.0, "mashing still combos -- the second hit lands (%.1f damage)" % result.x)


func _test_timing_the_cancel_pays(attacker: Fighter, victim: Fighter) -> void:
	var mashed := await _chain_with_delay(attacker, victim, MASH_DELAY)

	# Sweep the delay to find where the window actually is, rather than
	# re-deriving it here and duplicating the fighter's own arithmetic.
	var best_damage := 0.0
	var on_beat_delays: Array[int] = []
	for delay in [MASH_DELAY, 6, 9, 12, 15, 18, 21, 24]:
		var result := await _chain_with_delay(attacker, victim, delay)
		if result.y > 0:
			on_beat_delays.append(delay)
			best_damage = maxf(best_damage, result.x)

	_check(not on_beat_delays.is_empty(),
		"there is a delay that scores on beat (hit at %s)" % str(on_beat_delays))
	_check(not on_beat_delays.has(MASH_DELAY), "pressing instantly never scores on beat")
	_check(best_damage > mashed.x,
		"an on-beat follow-up hits harder than a mashed one (%.1f vs %.1f)"
			% [best_damage, mashed.x])


## Runs jab into its follow-up with `delay` ticks between the two presses.
## Returns the follow-up's damage in x and the resulting flow in y.
func _chain_with_delay(attacker: Fighter, victim: Fighter, delay: int) -> Vector2:
	await _stage(attacker, victim)
	var source := _source(attacker)

	_tap(source, InputFrame.Action.LIGHT)
	await _pinned_ticks(delay, attacker, victim)
	_tap(source, InputFrame.Action.LIGHT)
	await _pinned_until_hits(2, attacker, victim, 100)

	var flow := attacker.flow
	var damage := _hits[1].damage if _hits.size() > 1 else 0.0
	await _pinned_ticks(30, attacker, victim)
	return Vector2(damage, flow)


# --- Feedback and flow ---

func _test_hit_shakes_the_camera(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	await _ticks_until_hit(attacker, victim, InputFrame.Action.HEAVY)
	_check(_camera.get_shake() > 0.0, "a hit shakes the camera (%.2f)" % _camera.get_shake())

	await _ticks(90)
	_check(is_zero_approx(_camera.get_shake()), "the shake decays back to nothing")


func _test_defeat_at_zero_health(attacker: Fighter, victim: Fighter) -> void:
	await _stage(attacker, victim)
	_defeats = 0
	victim.health = 1.0

	await _ticks_until_hit(attacker, victim, InputFrame.Action.HEAVY)
	await _ticks(5)

	_check(_defeats == 1, "dropping to zero health reports a defeat (%d)" % _defeats)
	# M2 has no stocks yet, so a defeated fighter comes straight back and
	# playtesting continues. Stocks arrive with the match flow in M4.
	_check(is_equal_approx(victim.health, victim.max_health),
		"a defeated fighter returns at full health (%.1f)" % victim.health)


# --- Local helpers ---

## Puts two fighters face to face on open floor with clean state, and parks
## everyone else back on their spawn so a bystander cannot wander into a hitbox.
func _stage(attacker: Fighter, victim: Fighter, gap := GAP,
		facing := Vector3.FORWARD) -> void:
	for fighter: Fighter in _fighters:
		fighter.respawn()
		_source(fighter).release_all()
		_source(fighter).move = Vector2.ZERO
		fighter.power = 0.0
		fighter.stamina = fighter.max_stamina

	attacker.global_position = STAGE
	attacker.snap_facing(facing)
	if victim != attacker:
		victim.global_position = STAGE + facing * gap
		victim.snap_facing(-facing)

	await _settle(attacker, victim)
	_hits.clear()
	_hit_ticks.clear()


## Waits until both fighters are actually standing, so a test never starts
## measuring while someone is still in the air.
func _settle(attacker: Fighter, victim: Fighter) -> void:
	for i in 120:
		await get_tree().physics_frame
		if i >= 8 and attacker.is_on_floor() and victim.is_on_floor():
			return


func _scaled_startup(fighter: Fighter, attack: AttackDef) -> int:
	return CombatMath.scale_ticks(
		attack.ticks_startup, fighter.character_def.get_attack_speed_scale())


## One-tick press, so the attack buffer sees exactly one edge.
func _tap(source: ScriptedInputSource, action: InputFrame.Action) -> void:
	source.hold(action, true)
	await get_tree().physics_frame
	source.hold(action, false)


## Ticks until the victim takes damage, returning how many ticks that took.
func _ticks_until_hit(attacker: Fighter, victim: Fighter,
		action: InputFrame.Action, limit := 120) -> int:
	var before := victim.health
	_tap(_source(attacker), action)
	for i in limit:
		await get_tree().physics_frame
		if victim.health < before - 0.001:
			return i
	return -1


func _await_hit(limit := 120) -> bool:
	var before := _hits.size()
	for i in limit:
		await get_tree().physics_frame
		if _hits.size() > before:
			return true
	return false


## Holds both fighters in place while ticking, so a test of cancel logic is not
## secretly a test of whether knockback moved the victim out of range.
## Pins both fighters until the recorded hit count reaches `target`.
func _pinned_until_hits(target: int, attacker: Fighter, victim: Fighter, limit: int) -> void:
	var attacker_at := attacker.global_position
	var victim_at := victim.global_position
	for i in limit:
		attacker.global_position = attacker_at
		victim.global_position = victim_at
		await get_tree().physics_frame
		if _hits.size() >= target:
			return


func _pinned_ticks(count: int, attacker: Fighter, victim: Fighter) -> void:
	var attacker_at := attacker.global_position
	var victim_at := victim.global_position
	for i in count:
		attacker.global_position = attacker_at
		victim.global_position = victim_at
		await get_tree().physics_frame
