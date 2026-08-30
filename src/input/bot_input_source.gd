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
