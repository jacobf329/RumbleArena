## An AI player.
##
## A bot is an InputSource like any other: it fills an InputFrame and the
## fighter consumes it without knowing the difference. That is the whole payoff
## of never letting fighters poll Input directly -- the AI plays the actual game
## through the actual buttons, so it cannot reach past the rules, and anything a
## bot can do a player can do.
class_name BotInputSource
extends InputSource

## Device ids below this are bots. Keyboard is -1, real pads are 0 and up, and
## the test harness's scripted source sits at -100, so bots start well clear of
## all three: two sources reporting the same device would let PlayerManager
## think a seat was already taken.
const DEVICE_BASE := -1000

## How close a bot wants to be before throwing hands.
const ENGAGE_RANGE := 1.6
## Beyond this it walks in a straight line; inside it starts circling.
const APPROACH_RANGE := 4.0
## Seconds between reconsidering who to fight.
const RETARGET_INTERVAL := 1.2
## Default for crowd_pull below.
const DEFAULT_CROWD_PULL := 0.9

# Bots have no navigation mesh. They walk at whoever they are fighting, which is
# fine on a flat floor and useless the moment the arena has a ramp, a platform
# edge or a pillar in the way -- and this one has all three. Rather than build
# pathfinding for a four-bot couch game, they notice they have stopped moving
# and deal with it the way a player does: jump, then commit to going round for a
# moment so they do not immediately walk back into the same corner.
## Seconds of walking into something before a bot tries to get over or around it.
const STALL_TIME := 0.25
## Below this ground speed, a bot that is asking to move is not moving.
const STALL_SPEED := 1.4
## How long it commits to going around after a stall.
const DETOUR_TIME := 0.8

# The arena is half the game, and until now bots played the other half. Nothing
# stopped them picking things up except that nobody had told them to, which
# quietly made every prop a human-only advantage -- the exact opposite of what
# "the arena is a weapon" is for.
## How far a bot will leave a fight to go and fetch something.
const FETCH_RANGE := 8.0
## Below this it just punches: walking to a crate to throw at somebody standing
## next to you is worse than hitting them.
const FETCH_WORTH_IT := 5.5
## Extra metres a bot will walk, over and above going straight at its target, to
## pick something up on the way.
##
## Measured as a detour rather than as "is it near me", because near me and
## behind me is the whole arena's width away from the fight. The first version
## scored on proximity alone and four bots spent an entire match orbiting props
## at opposite corners: the fight was spread over twenty metres a hundred
## percent of the time, and they attacked a third as often.
const MAX_DETOUR := 4.5
## Default for fetch_chance below.
const DEFAULT_FETCH_CHANCE := 0.35
## Quiet period after a throw, so it does not immediately go looking again.
const FETCH_REST := 4.0
## Seconds between looking around for something to pick up. Short on purpose:
## the scan is a handful of children, and a long cooldown does not save anything
## worth having -- it just means that after one look that found nothing, the bot
## spends the next few seconds walking out of range of the crate it would have
## picked up, and never comes back for it.
const FETCH_INTERVAL := 0.35
## How far it will throw.
const THROW_RANGE := 11.0
## How squarely it has to be facing before it lets go. 0.86 is thirty degrees
## of error, which over even three metres is a clean miss -- and since the bot
## walks at its target while carrying, waiting for a tighter line costs it
## almost nothing.
const THROW_AIM := 0.97
## It throws anyway after this long, rather than shuffling for a perfect line.
const CARRY_PATIENCE := 3.0
## Fuse remaining below which a carried barrel goes NOW, aimed or not.
const PANIC_FUSE := 1.1
## Clearance kept from somebody else's lit barrel.
const BLAST_MARGIN := 1.4

var fighter: Fighter
## 0 is a punching bag, 1 is genuinely irritating. Drives reaction time, how
## often it guards, and how close its combo timing gets to the rhythm window.
var skill: float = 0.5
## How strongly this bot prefers whoever is in the middle of the scrum over
## whoever is merely closest.
##
## Picking the nearest opponent looks obviously right and is obviously wrong
## here: four bots pair off into two duels in opposite corners, which is the one
## thing a single shared camera cannot frame. A human drifts toward the action
## because that is where the game is; the AI has to be told to. Tunable per bot
## so the effect can be measured rather than asserted.
var crowd_pull: float = DEFAULT_CROWD_PULL
## Chance of bothering with a prop at all when the scan comes round. A bot that
## fetched every time it could would be a bot that never fights.
##
## Per bot rather than a constant for the same reason crowd_pull is: it is a
## personality knob, and a check of "can this bot fetch at all" should not turn
## on a coin flip. Left as a constant it made that test fail a third of the time.
var fetch_chance: float = DEFAULT_FETCH_CHANCE

var _index: int
## A Node3D rather than a Fighter, because an afterimage is a legitimate thing
## to be fighting. Everything the bot asks of a target -- where it is, whether
## it is still there, what it is doing -- a decoy can answer, and requiring a
## real Fighter here would have made Jinsoku's signature power do nothing at all
## to a CPU. Duck-typed on purpose: the decoy earns its place by being
## convincing, not by inheriting.
var _target: Node3D
var _retarget := 0.0
var _attack_cooldown := 0.0
var _reaction := 0.0
var _strafe := 1.0
var _strafe_timer := 0.0
var _stall := 0.0
var _detour := 0.0
var _fetch_timer := 0.0
var _carry_timer := 0.0
var _errand: Interactable = null
var _desired_move := Vector2.ZERO
var _tap_queue: Array[InputFrame.Action] = []
var _holds: Dictionary = {}


func _init(bot_index: int, bot_skill := 0.5) -> void:
	_index = bot_index
	skill = clampf(bot_skill, 0.0, 1.0)


func get_display_name() -> String:
	return "CPU"


func get_device_id() -> int:
	return DEVICE_BASE - _index


func _read(f: InputFrame) -> void:
	if not is_instance_valid(fighter):
		return

	_think(1.0 / float(Engine.physics_ticks_per_second))

	f.move = _desired_move
	f.aim = _desired_move

	# A queued tap is set for exactly this frame, which is one clean
	# just-pressed edge -- the same thing a player's thumb produces.
	for action in _tap_queue:
		f.set_action(action, true)
	_tap_queue.clear()

	for action: InputFrame.Action in _holds:
		if _holds[action] > 0:
			f.set_action(action, true)


func _think(delta: float) -> void:
	for action: InputFrame.Action in _holds:
		_holds[action] = maxi(_holds[action] - 1, 0)

	_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	_fetch_timer = maxf(_fetch_timer - delta, 0.0)
	_reaction = maxf(_reaction - delta, 0.0)
	_retarget = maxf(_retarget - delta, 0.0)
	_strafe_timer = maxf(_strafe_timer - delta, 0.0)

	# A bot with no control of itself should not be issuing orders either.
	if fighter.is_eliminated or fighter.get_state_id() in [
		FighterState.HITSTUN, FighterState.KNOCKDOWN
	]:
		_desired_move = Vector2.ZERO
		return

	if _retarget <= 0.0 or not _is_valid(_target):
		_target = _pick_target()
		_retarget = RETARGET_INTERVAL

	if not _is_valid(_target):
		_desired_move = Vector2.ZERO
		return

	var offset := _target.global_position - fighter.global_position
	var flat := Vector3(offset.x, 0.0, offset.z)
	var distance := flat.length()

	# Getting clear of a live barrel outranks everything, including whatever it
	# was in the middle of. Nothing else in the arena can take a third of your
	# health while you are looking the other way.
	if _avoid_blasts():
		_check_for_a_wall(delta)
		return

	if _handle_errands(delta, flat, distance):
		_check_for_a_wall(delta)
		return

	_move_toward(flat, distance)
	_check_for_a_wall(delta)
	if _reaction <= 0.0:
		_fight(distance)


## Straight in from far away, circling once close, so two bots do not simply
## shove into each other and stall.
func _move_toward(flat: Vector3, distance: float) -> void:
	if distance < 0.05:
		_desired_move = Vector2.ZERO
		return

	var direction := flat.normalized()
	if _detour > 0.0:
		# Mostly sideways, still leaning toward the target, so a detour rounds an
		# obstacle instead of walking away from the fight.
		var around := Vector3(-direction.z, 0.0, direction.x) * _strafe
		_desired_move = fighter.to_input_space((direction * 0.35 + around).normalized())
		return

	if distance < APPROACH_RANGE:
		if _strafe_timer <= 0.0:
			_strafe = -_strafe
			_strafe_timer = randf_range(0.7, 1.6)
		var sideways := Vector3(-direction.z, 0.0, direction.x) * _strafe
		var closing := 1.0 if distance > ENGAGE_RANGE else -0.25
		direction = (direction * closing + sideways * 0.7).normalized()

	_desired_move = fighter.to_input_space(direction)


# --- Using the arena ---

## Walks away from anybody else's lit barrel. Its own is a weapon, not a hazard.
func _avoid_blasts() -> bool:
	var escape := Vector3.ZERO
	for node in fighter.get_tree().get_nodes_in_group(&"barrels"):
		var barrel := node as ExplosiveBarrel
		if barrel == null or not is_instance_valid(barrel) or not barrel.is_lit():
			continue
		if barrel.carrier == fighter:
			continue
		var offset := fighter.global_position - barrel.global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		if flat.length() > barrel.blast_radius + BLAST_MARGIN:
			continue
		if flat.length_squared() < 0.01:
			flat = fighter.get_facing_direction()
		escape += flat.normalized()

	if escape == Vector3.ZERO:
		return false
	_desired_move = fighter.to_input_space(escape.normalized())
	return true


## Fetching something to throw, and throwing it. Returns whether the errand owns
## this tick's movement and interact button.
func _handle_errands(delta: float, to_target: Vector3, distance: float) -> bool:
	if fighter.carried != null:
		_carry_timer += delta
		return _throw_it(to_target, distance)

	_carry_timer = 0.0
	if not _worth_fetching(_errand):
		_errand = null
	# Stalled on the way: the errand path does its own steering, so it cannot
	# use the detour the wall check sets up. Something is between the bot and
	# the prop, and standing there shoving at it is worse than forgetting it.
	if _detour > 0.0:
		_errand = null
		_fetch_timer = FETCH_REST
		return false

	if _errand == null:
		if _fetch_timer > 0.0 or distance < FETCH_WORTH_IT:
			return false
		_fetch_timer = FETCH_INTERVAL
		if randf() > fetch_chance * (0.5 + skill):
			return false
		_errand = _find_something_to_carry(to_target)
		if _errand == null:
			return false

	# Walk to it, and take it the moment the fighter's own probe agrees it is in
	# reach -- the same signal the prompt above a player's head is reading.
	var reach := _errand.global_position - fighter.global_position
	_desired_move = fighter.to_input_space(Vector3(reach.x, 0.0, reach.z).normalized())
	if fighter.interaction_target == _errand:
		_tap(InputFrame.Action.INTERACT)
		_errand = null
	return true


func _throw_it(to_target: Vector3, distance: float) -> bool:
	var barrel := fighter.carried as ExplosiveBarrel
	var panicking := barrel != null and barrel.fuse_left() < PANIC_FUSE

	# Line up on the target: the fighter faces where it is walking, so aiming and
	# closing are the same action.
	var aim := Vector3(to_target.x, 0.0, to_target.z)
	if aim.length_squared() > 0.0001:
		_desired_move = fighter.to_input_space(aim.normalized())

	var facing: Vector3 = fighter.get_facing_direction()
	var squared_up := aim.length_squared() > 0.0001 \
		and facing.dot(aim.normalized()) > THROW_AIM
	var in_range := distance < THROW_RANGE

	if panicking or _carry_timer > CARRY_PATIENCE or (squared_up and in_range):
		_tap(InputFrame.Action.INTERACT)
		_carry_timer = 0.0
		_fetch_timer = FETCH_REST
	return true


## The best thing to pick up on the way to the fight.
##
## Nothing already in somebody else's hands, and nothing this bot would be
## refused -- walking to a pillar it cannot lift would look exactly like a bot
## that is broken. Scored by how far it adds to the trip it was already making,
## so a crate directly between it and its target is nearly free and one behind
## it is not worth having.
func _find_something_to_carry(to_target: Vector3) -> Interactable:
	var here: Vector3 = fighter.global_position
	var there := here + to_target
	var direct := to_target.length()

	var best: Interactable = null
	var best_detour := MAX_DETOUR
	for node in fighter.get_tree().get_nodes_in_group(&"arena"):
		var arena := node as Arena
		if arena == null:
			continue
		for child in arena.interactable_root().get_children():
			var liftable := child as Liftable
			if liftable == null or not _worth_fetching(liftable):
				continue
			var at: Vector3 = liftable.global_position
			if here.distance_to(at) > FETCH_RANGE:
				continue
			var detour := here.distance_to(at) + at.distance_to(there) - direct
			if detour < best_detour:
				best_detour = detour
				best = liftable
	return best


## Untyped on purpose. An errand can be freed between one tick and the next -- a
## barrel detonates, debris is thrown and consumed -- and a freed object cannot
## be passed to a typed parameter at all: GDScript refuses the cast, the call
## errors, and the function returns its default rather than answering. That is
## the third time that has bitten in this file, and it fails quietly every time.
func _worth_fetching(thing) -> bool:
	if thing == null or not is_instance_valid(thing):
		return false
	var interactable := thing as Interactable
	if interactable == null:
		return false
	return interactable.is_offered(fighter) and interactable.can_use(fighter)


## Asking to move and not moving means something is in the way.
func _check_for_a_wall(delta: float) -> void:
	_detour = maxf(_detour - delta, 0.0)

	var walking := fighter.get_state_id() in [FighterState.RUN, FighterState.IDLE]
	var speed := Vector2(fighter.velocity.x, fighter.velocity.z).length()
	if walking and _desired_move.length() > 0.5 and speed < STALL_SPEED:
		_stall += delta
	else:
		# Decays faster than it builds, so a momentary bump is not a wall.
		_stall = maxf(_stall - delta * 2.0, 0.0)

	if _stall >= STALL_TIME:
		_stall = 0.0
		_detour = DETOUR_TIME
		_strafe = -_strafe
		_tap(InputFrame.Action.JUMP)


func _fight(distance: float) -> void:
	# Guarding is the difference between a bot that trades and one that plays.
	if distance < ENGAGE_RANGE * 1.4 and _target_state() == FighterState.ATTACK:
		if randf() < 0.25 + 0.5 * skill:
			_hold(InputFrame.Action.BLOCK, 22)
			_reaction = _reaction_time()
			return
		if randf() < 0.35 * skill:
			_tap(InputFrame.Action.DODGE)
			_reaction = _reaction_time()
			return

	if distance > ENGAGE_RANGE * 1.25 or _attack_cooldown > 0.0:
		return

	# Grab a guard rather than beating on it: the bot should demonstrate the
	# rock-paper-scissors rather than lose to it.
	if _target_state() == FighterState.BLOCK and randf() < 0.4 + 0.4 * skill:
		_tap(InputFrame.Action.GRAB)
		_attack_cooldown = 1.1
		return

	var signature: Power = fighter.character_def.signature
	if signature != null and fighter.power >= signature.power_cost and randf() < 0.25 * skill:
		_tap(InputFrame.Action.SIGNATURE)
		_attack_cooldown = 1.4
		return

	_tap(InputFrame.Action.LIGHT)
	# Higher skill presses closer to the cancel window, so a good bot chains and
	# a poor one mashes out of rhythm.
	_attack_cooldown = lerpf(0.42, 0.20, skill)


## What the target appears to be doing. A decoy is doing nothing, which is
## exactly right: the bot neither guards against it nor tries to grab its guard,
## it just walks up and hits it -- and pops it.
func _target_state() -> StringName:
	if _target != null and _target.has_method(&"get_state_id"):
		return _target.get_state_id()
	return FighterState.IDLE


func _reaction_time() -> float:
	return lerpf(0.42, 0.10, skill)


func _pick_target() -> Node3D:
	var candidates: Array[Node3D] = []
	for node in fighter.get_tree().get_nodes_in_group(&"fighters"):
		var other := node as Fighter
		if _is_valid(other) and other != fighter:
			candidates.append(other)
	# Decoys are considered alongside the real thing, which is the only way an
	# afterimage can fool anybody who is not a person.
	for node in fighter.get_tree().get_nodes_in_group(&"afterimages"):
		var decoy := node as Afterimage
		if decoy != null and is_instance_valid(decoy) and decoy.owner_fighter != fighter:
			candidates.append(decoy)
	if candidates.is_empty():
		return null

	var crowd := _crowd_centre(candidates)
	# Node3D, not Fighter: a decoy that could be scored but never stored is a
	# decoy nobody is ever fooled by.
	var best: Node3D = null
	var best_score := INF
	for other in candidates:
		var score := fighter.global_position.distance_to(other.global_position) \
			+ crowd_pull * other.global_position.distance_to(crowd)
		if score < best_score:
			best_score = score
			best = other
	return best


## Where the fight is: the centre of everybody except this bot. Counting itself
## would drag the centre toward wherever it had already wandered, which is
## exactly the drift the pull exists to correct.
func _crowd_centre(candidates: Array[Node3D]) -> Vector3:
	var sum := Vector3.ZERO
	for other in candidates:
		sum += other.global_position
	return sum / float(candidates.size())


## True for anything still worth walking at. Reads is_eliminated off the node
## rather than typing the parameter, so a decoy -- which has no such property --
## counts as present for as long as it exists.
##
## Compared against true rather than cast: Object.get returns null for a
## property that does not exist, and bool(null) is a runtime error in GDScript.
## It type-checks, it imports clean, and it fails at runtime into the function's
## default -- which is false, so every decoy read as "not there" and the bot
## stood still staring at one.
func _is_valid(other: Node3D) -> bool:
	if other == null or not is_instance_valid(other):
		return false
	return other.get(&"is_eliminated") != true


func _tap(action: InputFrame.Action) -> void:
	if not _tap_queue.has(action):
		_tap_queue.append(action)


func _hold(action: InputFrame.Action, ticks: int) -> void:
	_holds[action] = ticks
