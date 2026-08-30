## Headless verification of the M3 stat-gated arena.
##
## The permission rule is the spine of the design, so these checks are as much
## about what each character is *refused* as what they can do.
extends TestHarness

const REACH := 1.15

var _fighters: Array[Fighter] = []
var _kurogane: Fighter   # STR 5 / TECH 1 -- lifts anything, hacks nothing
var _null: Fighter       # STR 1 / TECH 5 -- hacks anything, lifts almost nothing
var _jinsoku: Fighter    # STR 2 -- breaks racks, cannot lift pillars
var _yamabuki: Fighter


func _init() -> void:
	test_name = "M3 interaction test"


func _run() -> void:
	_kurogane = await _join(0)
	_null = await _join(1)
	_jinsoku = await _join(2)
	_yamabuki = await _join(3)
	_fighters = [_kurogane, _null, _jinsoku, _yamabuki]
	await _ticks(30)

	_section("The permission rule")
	_test_gates_are_exclusive()
	await _test_probe_finds_what_is_in_front()
	await _test_refusal_names_the_requirement()

	_section("Lifting and throwing")
	await _test_lifting_is_strength_gated()
	await _test_carrying_slows_you_down()
	await _test_carrying_prevents_attacking()
	await _test_a_thrown_pillar_hurts()
	await _test_dying_returns_what_you_carried()

	_section("Breaking")
	await _test_breaking_is_strength_gated()
	await _test_breaking_leaves_debris_anyone_can_lift()

	_section("Climbing")
	await _test_climbing_is_agility_gated()
	await _test_climbing_reaches_the_tower_top()

	_section("Hacking")
	await _test_hacking_is_tech_gated()
	await _test_a_hacked_turret_shoots_the_others()


# --- The permission rule ---

## Every interactable in the arena is gated to exactly one of the four staged
## characters, or to everyone. That is the teaching design: you learn the system
## by being refused, and learn the roster by seeing what you are refused.
func _test_gates_are_exclusive() -> void:
	var pillar := _pillar()
	var turret := _turret()

	_check(pillar.can_use(_kurogane), "Kurogane (STR 5) can lift the pillar")
	for other: Fighter in [_null, _jinsoku, _yamabuki]:
		_check(not pillar.can_use(other),
			"%s cannot lift the pillar" % other.character_def.display_name)

	_check(turret.can_use(_null), "Null (TECH 5) can hack the turret")
	for other: Fighter in [_kurogane, _jinsoku, _yamabuki]:
		_check(not turret.can_use(other),
			"%s cannot hack the turret" % other.character_def.display_name)


func _test_probe_finds_what_is_in_front() -> void:
	await _stand_at(_kurogane, _pillar())
	_check(_kurogane.interaction_target == _pillar(),
		"standing in front of the pillar targets it")

	await _park(_kurogane)
	_check(_kurogane.interaction_target == null,
		"standing in open floor targets nothing")


## A refused prompt still appears, and says what would be needed.
func _test_refusal_names_the_requirement() -> void:
	var pillar := _pillar()
	await _stand_at(_null, pillar)

	_check(_null.interaction_target == pillar,
		"a fighter who cannot use something is still offered it")
	var prompt := pillar.prompt_text(_null)
	_check(prompt.contains("STRENGTH") and prompt.contains("4"),
		"the refusal names the requirement (\"%s\")" % prompt)
	_check(pillar.prompt_text(_kurogane).begins_with("Lift"),
		"a fighter who qualifies is offered the verb instead (\"%s\")"
			% pillar.prompt_text(_kurogane))
	await _park(_null)


# --- Lifting and throwing ---

func _test_lifting_is_strength_gated() -> void:
	var pillar := _pillar()

	await _stand_at(_null, pillar)
	await _press_interact(_null)
	_check(_null.carried == null, "Null cannot pick the pillar up")
	_check(pillar.carrier == null, "the pillar stays where it is")
	await _park(_null)

	await _stand_at(_kurogane, pillar)
	await _press_interact(_kurogane)
	_check(_kurogane.carried == pillar, "Kurogane picks the pillar up")
	_check(pillar.carrier == _kurogane, "the pillar knows who is holding it")

	await _ticks(10)
	_check(pillar.global_position.distance_to(_kurogane.global_position) < 2.6,
		"the pillar rides with its carrier")


func _test_carrying_slows_you_down() -> void:
	var loaded := await _measure_run(_kurogane)
	_kurogane.carried.release()
	_kurogane.carried = null
	await _ticks(20)
	var free := await _measure_run(_kurogane)

	_check(loaded < free * 0.85,
		"carrying a pillar costs real speed (%.1f vs %.1f units)" % [loaded, free])


func _test_carrying_prevents_attacking() -> void:
	var pillar := _pillar()
	await _stand_at(_kurogane, pillar)
	await _press_interact(_kurogane)
	_check(_kurogane.carried == pillar, "picked the pillar back up")

	var before := _kurogane.attacks_started
	_tap(_source(_kurogane), InputFrame.Action.LIGHT)
	await _ticks(20)
	_check(_kurogane.attacks_started == before,
		"you cannot punch with your hands full")


func _test_a_thrown_pillar_hurts() -> void:
	var pillar := _pillar()
	_check(_kurogane.carried == pillar, "still carrying for the throw")
	if _kurogane.carried != pillar:
		return

	# Line the victim up down-range and throw at them.
	_kurogane.global_position = Vector3(-8, 0.3, 12)
	_kurogane.snap_facing(Vector3.RIGHT)
	_yamabuki.global_position = Vector3(-4.2, 0.3, 12)
	_yamabuki.velocity = Vector3.ZERO
	await _ticks(12)

	var health := _yamabuki.health
	await _press_interact(_kurogane)
	_check(_kurogane.carried == null, "throwing empties your hands")

	var hit := false
	for i in 90:
		await get_tree().physics_frame
		if _yamabuki.health < health - 0.01:
			hit = true
			break
	_check(hit, "a thrown pillar hits for %.1f" % (health - _yamabuki.health))
	await _ticks(40)
	await _park(_yamabuki)


func _test_dying_returns_what_you_carried() -> void:
	var pillar := _pillar()
	pillar.release()
	await _stand_at(_kurogane, pillar)
	await _press_interact(_kurogane)
	_check(_kurogane.carried == pillar, "carrying before the respawn")

	_kurogane.respawn()
	await _ticks(5)
	_check(_kurogane.carried == null and pillar.carrier == null,
		"respawning puts the pillar back rather than removing it from the match")
	await _park(_kurogane)


# --- Breaking ---

func _test_breaking_is_strength_gated() -> void:
	var rack := _rack("RackWest")
	if rack == null:
		_check(false, "the west rack exists")
		return

	var full := rack.health
	_check(not rack.can_be_broken_by(_null), "Null (STR 1) is too weak to break a rack")
	_check(rack.can_be_broken_by(_jinsoku), "Jinsoku (STR 2) can break a rack")

	_check(not rack.take_attack(50.0, _null), "Null's hit does nothing to the rack")
	_check(is_equal_approx(rack.health, full), "the rack takes no damage from Null")

	_check(rack.take_attack(10.0, _jinsoku), "Jinsoku's hit damages the rack")
	_check(rack.health < full, "the rack loses health (%.1f of %.1f)" % [rack.health, full])


func _test_breaking_leaves_debris_anyone_can_lift() -> void:
	var rack := _rack("RackEast")
	if rack == null:
		_check(false, "the east rack exists")
		return

	var container := rack.get_parent()
	var before := _count_liftables(container)
	rack.take_attack(999.0, _kurogane)
	await _ticks(5)

	var after := _count_liftables(container)
	_check(after > before, "breaking a rack leaves debris (%d -> %d)" % [before, after])

	# Debris is mass class 1, so the fighter who could not break it can still
	# throw the pieces -- the arena stays useful to everyone.
	var debris := _newest_liftable(container)
	_check(debris != null and debris.can_use(_null),
		"even Null can lift the debris it could not create")


# --- Climbing ---

## Double jumping already keys off AGILITY 3, so climbing is pitched at 4 to
## give the acrobat something the other three genuinely cannot do.
func _test_climbing_is_agility_gated() -> void:
	var wall := _wall()
	_check(wall.can_use(_yamabuki), "Yamabuki (AGI 5) can climb")
	for other: Fighter in [_kurogane, _null, _jinsoku]:
		_check(not wall.can_use(other),
			"%s (AGI %d) cannot climb" % [
				other.character_def.display_name, other.character_def.stat_agility])

	await _stand_at_wall(_jinsoku, wall)
	_check(_jinsoku.interaction_target == wall, "Jinsoku is in range of the wall")
	await _press_interact(_jinsoku)
	_check(_jinsoku.get_state_id() != FighterState.CLIMB,
		"an AGI 3 fighter is refused the climb (%s)" % _jinsoku.get_state_id())
	await _park(_jinsoku)


func _test_climbing_reaches_the_tower_top() -> void:
	var wall := _wall()
	await _stand_at_wall(_yamabuki, wall)
	var ground_y := _yamabuki.global_position.y

	await _press_interact(_yamabuki)
	_check(_yamabuki.get_state_id() == FighterState.CLIMB,
		"Yamabuki gets on the wall (%s)" % _yamabuki.get_state_id())
	if _yamabuki.get_state_id() != FighterState.CLIMB:
		return

	# Hold up until the mantle fires.
	_source(_yamabuki).move = Vector2(0, 1)
	var peak := ground_y
	var mantled := false
	for i in 400:
		await get_tree().physics_frame
		peak = maxf(peak, _yamabuki.global_position.y)
		if _yamabuki.get_state_id() != FighterState.CLIMB:
			mantled = true
			break
	_source(_yamabuki).move = Vector2.ZERO

	_check(peak > ground_y + 4.0, "climbing gains real height (%.1f metres)" % (peak - ground_y))
	_check(mantled, "reaching the top mantles off the wall")

	await _ticks(60)
	_check(_yamabuki.global_position.y > wall.top_y - 1.0,
		"she ends up on top of the tower (y %.1f)" % _yamabuki.global_position.y)

	# The reward for getting up there is reachable only by climbing: the tower is
	# 7m and no double jump clears that from the floor.
	var prize := _main.get_node_or_null("Arena/Interactables/TowerPrize") as Liftable
	_check(prize != null and prize.global_position.y > 6.5,
		"there is something on top worth the climb")
	await _park(_yamabuki)


# --- Hacking ---

func _test_hacking_is_tech_gated() -> void:
	var turret := _turret()

	await _stand_at(_kurogane, turret)
	# Assert he can actually see it first: before the turret's reach was widened
	# this check passed only because nothing on the floor could target a turret
	# on the ceiling at all.
	_check(_kurogane.interaction_target == turret,
		"Kurogane is in range of the turret")
	await _press_interact(_kurogane)
	_check(turret.controller == null, "Kurogane (TECH 1) cannot hack the turret")
	await _park(_kurogane)

	await _stand_at(_null, turret)
	await _press_interact(_null)
	_check(turret.controller == _null, "Null (TECH 5) hacks the turret")
	await _park(_null)


## The point of the TECH gate: a character who loses every straight fight can
## still turn the room against everyone else.
func _test_a_hacked_turret_shoots_the_others() -> void:
	var turret := _turret()
	turret.controller = _null

	_null.global_position = turret.global_position + Vector3(0, -5.0, 1.5)
	_kurogane.global_position = turret.global_position + Vector3(2.0, -5.0, 0)
	for fighter: Fighter in [_null, _kurogane]:
		fighter.velocity = Vector3.ZERO
		fighter.health = fighter.max_health
	await _ticks(20)

	var target_health := _kurogane.health
	var owner_health := _null.health
	await _ticks(200)

	_check(_kurogane.health < target_health,
		"the hacked turret shoots the fighter who did not hack it (%.1f -> %.1f)"
			% [target_health, _kurogane.health])
	_check(is_equal_approx(_null.health, owner_health),
		"and never shoots the hacker who owns it (%.1f)" % _null.health)
	turret.controller = null


# --- Local helpers ---

func _pillar() -> Liftable:
	return _main.get_node("Arena/Interactables/PillarWest") as Liftable


func _turret() -> HackableTurret:
	return _main.get_node("Arena/Interactables/TurretWest") as HackableTurret


func _wall() -> Climbable:
	return _main.get_node("Arena/Interactables/TowerFace") as Climbable


## Stands a fighter against the climbable face, on the ground, facing the wall.
func _stand_at_wall(fighter: Fighter, wall: Climbable) -> void:
	var normal := wall.outward_normal()
	fighter.global_position = Vector3(
		wall.global_position.x, 0.3, wall.global_position.z) + normal * 0.9
	fighter.velocity = Vector3.ZERO
	fighter.snap_facing(-normal)
	_source(fighter).release_all()
	_source(fighter).move = Vector2.ZERO
	await _ticks(14)


func _rack(name: String) -> Breakable:
	return _main.get_node_or_null("Arena/Interactables/" + name) as Breakable


func _count_liftables(container: Node) -> int:
	var count := 0
	for child in container.get_children():
		if child is Liftable:
			count += 1
	return count


func _newest_liftable(container: Node) -> Liftable:
	var found: Liftable = null
	for child in container.get_children():
		if child is Liftable and (child as Liftable).mass_class == 1:
			found = child
	return found


## Stands a fighter just in front of an object, facing it, and lets the probe run.
func _stand_at(fighter: Fighter, target: Node3D) -> void:
	var ground := target.global_position
	ground.y = 0.3
	var approach := Vector3(0, 0, 1) * REACH
	fighter.global_position = ground + approach
	fighter.velocity = Vector3.ZERO
	fighter.snap_facing(-approach.normalized())
	_source(fighter).release_all()
	_source(fighter).move = Vector2.ZERO
	await _ticks(12)


## Moves a fighter well clear of every interactable.
func _park(fighter: Fighter) -> void:
	fighter.global_position = Vector3(0, 0.3, 14.5)
	fighter.velocity = Vector3.ZERO
	_source(fighter).release_all()
	_source(fighter).move = Vector2.ZERO
	await _ticks(12)


func _press_interact(fighter: Fighter) -> void:
	var source := _source(fighter)
	source.hold(InputFrame.Action.INTERACT, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(InputFrame.Action.INTERACT, false)
	await _ticks(4)


func _tap(source: ScriptedInputSource, action: InputFrame.Action) -> void:
	source.hold(action, true)
	await get_tree().physics_frame
	source.hold(action, false)


## Distance covered running flat out for a fixed time.
func _measure_run(fighter: Fighter) -> float:
	fighter.global_position = Vector3(-9, 0.3, 14.5)
	fighter.velocity = Vector3.ZERO
	await _ticks(14)
	var start := fighter.global_position
	_source(fighter).move = Vector2(1, 0)
	await _ticks(45)
	var distance := fighter.global_position.distance_to(start)
	_source(fighter).move = Vector2.ZERO
	await _ticks(20)
	return distance
