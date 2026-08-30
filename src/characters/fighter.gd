## A player-controlled ninja.
##
## Reads intent only from an InputFrame -- never from Input directly. All feel
## constants that vary per character come from CharacterDef, so this class stays
## character-agnostic (GAME_DESIGN.md section 9).
class_name Fighter
extends CharacterBody3D

const DEFAULT_MOVE_SET := preload("res://src/combat/movesets/standard.tres")

## How long after a press a jump stays queued, so an early press still fires.
const JUMP_BUFFER := 0.12
## How long after walking off a ledge a ground jump is still allowed.
const COYOTE_TIME := 0.10
## Extra gravity while falling; makes the jump arc snappy instead of floaty.
const FALL_MULTIPLIER := 1.45
## Upward velocity kept when the jump button is released early.
const JUMP_CUT := 0.42
## An air jump is slightly weaker than the one off the floor.
const AIR_JUMP_SCALE := 0.92
## Below this height a fighter has fallen out of the arena and is put back.
const FALL_OUT_HEIGHT := -12.0

## Ticks an attack press stays queued. Without this, cancelling into the next
## link means hitting the exact frame the window opens, which no one can do.
const ATTACK_BUFFER_TICKS := 16
const DODGE_STAMINA := 24.0
const DODGE_INVULNERABLE_TICKS := 9
const STAMINA_REGEN_PER_SECOND := 22.0
const STAMINA_REGEN_DELAY := 0.35
## Ticks the body flashes white on being hit.
const HIT_FLASH_TICKS := 6
## Drag applied to knockback, so a hit carries rather than stopping dead.
const HITSTUN_DRAG := 4.0
## How far in front of a fighter the interaction probe reaches.
const INTERACT_REACH := 1.7
## How much control an attack leaves you: almost none.
const ATTACK_DRIFT_DRAG := 30.0

signal damaged(result: HitResult)
signal defeated()

@export var character_def: CharacterDef

var slot: PlayerSlot
var spawn_point := Vector3.ZERO

var move_set: MoveSet

var health: float = 100.0
var max_health: float = 100.0
var power: float = 0.0
var max_power: float = 100.0
var stamina: float = 100.0
var max_stamina: float = 100.0

## Set immediately before a transition into ATTACK / HITSTUN.
var pending_attack: AttackDef
var pending_hitstun: int = 0

## What this fighter is holding, and what it would act on if INTERACT were
## pressed right now. The target is tracked even when the fighter does not
## qualify, because a refused prompt is how the stat system teaches itself.
## Out of stocks and out of the match. The MatchManager decides this; a fighter
## never removes itself.
var is_eliminated := false

## Set by character select before the bell; takes precedence over the
## interaction prompt, which is not relevant until the match starts.
var select_prompt: String = ""

var carried: Liftable = null
var interaction_target: Interactable = null
## The wall this fighter is currently on, if any.
var climbing: Climbable = null

var _states: Dictionary = {}
var _state: FighterState
var _state_id: StringName = FighterState.IDLE

var _empty_frame := InputFrame.new()
var _gravity: float = 24.0

var _jump_buffer := 0.0
var _coyote := 0.0
var _air_jumps_left := 0
var _air_dashes_left := 0
var _dash_cooldown := 0.0

var _attack_buffer_action: int = -1
var _attack_buffer_ticks: int = 0
var _light_chain_index: int = 0
## Counts attacks entered by cancelling out of another, rather than started
## fresh. Purely observational, but it is the only unambiguous way to tell a
## real cancel from simply waiting out the recovery.
var cancel_count: int = 0
## Consecutive on-beat cancels. Rhythm is a streak, not a per-hit coin flip:
## the reward grows while the chain stays clean and resets the moment it does not.
var flow: int = 0
## Damage and knockback multiplier for the attack currently running.
var strike_scale: float = 1.0
var _pending_on_beat := false

var _power_cooldowns: Dictionary = {}
var _rampage_ticks := 0
var _rampage_armour := 0.0
var _rampage_bonus := 0.0
## Attacks entered, however they started. Observational.
var attacks_started: int = 0
var _attack_pressed_this_tick := false

var _hitstop: int = 0
var _invulnerable: int = 0
var _blockstun: int = 0
var _flash_ticks: int = 0
var _knockdown_pending := false
var _stamina_delay := 0.0
var _speed_before_move := 0.0

var _hitbox_shape := BoxShape3D.new()
var _hitbox_query := PhysicsShapeQueryParameters3D.new()
var _base_color := Color.WHITE

@onready var _visual: FighterVisual = $Visual
@onready var _nameplate: Label3D = $Nameplate
@onready var _prompt: Label3D = $Prompt


func _ready() -> void:
	if character_def == null:
		character_def = CharacterDef.new()
	move_set = character_def.move_set if character_def.move_set != null else DEFAULT_MOVE_SET

	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	max_health = character_def.get_max_health()
	max_power = character_def.get_max_power()
	max_stamina = character_def.get_max_stamina()
	health = max_health
	stamina = max_stamina
	_air_jumps_left = character_def.get_extra_jumps()
	_air_dashes_left = 1

	_hitbox_query.shape = _hitbox_shape
	_hitbox_query.collision_mask = Layers.HURTBOX | Layers.BREAKABLE
	_hitbox_query.collide_with_areas = true
	_hitbox_query.collide_with_bodies = false

	# Turrets and other arena logic look fighters up by group rather than by
	# walking the scene tree.
	add_to_group(&"fighters")

	_build_states()
	_apply_presentation()


func _build_states() -> void:
	var states: Array[FighterState] = [
		IdleState.new(), RunState.new(), AirState.new(), DashState.new(),
		AttackState.new(), HitstunState.new(), KnockdownState.new(), BlockState.new(),
		ClimbState.new(),
	]
	for state in states:
		state.setup(self)
		_states[state.get_id()] = state
	_state = _states[FighterState.IDLE]
	_state.enter(FighterState.IDLE)


## Every fighter shares one mesh and one texture; the slot colour is applied by
## rotating the hue of the texture's saturated crimson only, so four players
## read apart at a glance. Pillar P3.
func _apply_presentation() -> void:
	_base_color = slot.color if slot != null else Color.WHITE
	_visual.set_player_colour(_base_color)

	_nameplate.text = "%s  %s" % [
		slot.get_label() if slot != null else "--",
		character_def.display_name,
	]
	_nameplate.modulate = _base_color


func _physics_process(delta: float) -> void:
	# Hitstop freezes this fighter only. Global hitstop would be wrong in a
	# four-player game: the two players not involved in the hit would have their
	# own fight stuttered by someone else's.
	if _hitstop > 0:
		_hitstop -= 1
		# Presses still register while frozen. Hitstop lands exactly when a
		# player is inputting the next hit of a combo, so eating those presses
		# would make every chain feel like it dropped -- and the buffer must not
		# decay during a freeze either, or hitstop would shorten its own window.
		_capture_buffered_presses()
		_update_flash()
		return

	_update_timers(delta)
	_update_interaction()

	var next := _state.physics_update(delta)
	if next != FighterState.STAY:
		# Note the absence of a "different state" guard: cancelling one attack
		# into another is a transition from ATTACK to ATTACK, and suppressing
		# self-transitions would silently swallow every chain and confirm.
		# States already return STAY to mean "no change".
		_transition_to(next)

	_speed_before_move = velocity.length()
	# Climbing sets the transform directly, so it must not also run the body
	# solver: floor snapping would drag the fighter back down every tick, since
	# a tick's worth of climbing is shorter than the snap distance.
	if _state_id != FighterState.CLIMB:
		move_and_slide()
	_update_visual()

	if global_position.y < FALL_OUT_HEIGHT:
		respawn()


# --- Interaction ---

## Finds what this fighter is standing in front of and acts on an INTERACT press.
## Handled here rather than in each state so that picking something up does not
## need a branch in every movement state.
func _update_interaction() -> void:
	interaction_target = null if carried != null else _probe_for_interactable()

	if not get_input().is_just_pressed(InputFrame.Action.INTERACT):
		return
	if _state_id not in [FighterState.IDLE, FighterState.RUN, FighterState.AIR]:
		return

	if carried != null:
		var held := carried
		carried = null
		held.throw_from(self)
		return

	if interaction_target != null and interaction_target.can_use(self):
		if not interaction_target.use(self):
			return
		var liftable := interaction_target as Liftable
		if liftable != null:
			carried = liftable
			return
		var wall := interaction_target as Climbable
		if wall != null:
			climbing = wall
			_transition_to(FighterState.CLIMB)


## Nearest interactable in front of the fighter. Objects the fighter cannot use
## are still returned: the prompt shows them greyed out with the requirement.
func _probe_for_interactable() -> Interactable:
	var shape := SphereShape3D.new()
	shape.radius = INTERACT_REACH
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = Layers.INTERACTABLE
	query.collide_with_areas = true
	query.collide_with_bodies = false
	query.transform = Transform3D(
		Basis.IDENTITY,
		global_position + Vector3.UP * 0.9 + get_facing_direction() * 0.5)

	var best: Interactable = null
	var best_distance := INF
	for contact in get_world_3d().direct_space_state.intersect_shape(query, 8):
		var candidate := contact["collider"] as Interactable
		if candidate == null or not candidate.is_offered(self):
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


## Carrying something heavy slows you down; that is the cost that makes picking
## a pillar up a decision rather than a free upgrade.
func _speed_multiplier() -> float:
	return Liftable.CARRY_SPEED_PENALTY if carried != null else 1.0


func _update_prompt() -> void:
	if _prompt == null:
		return
	if select_prompt != "":
		_prompt.text = select_prompt
		_prompt.modulate = Color(1, 1, 1) if select_prompt.begins_with("READY") \
			else Color(0.86, 0.9, 1.0)
	elif carried != null:
		_prompt.text = "Throw %s" % carried.display_name
		_prompt.modulate = Color(0.85, 0.95, 1.0)
	elif interaction_target != null:
		_prompt.text = interaction_target.prompt_text(self)
		# Refusals are dimmed rather than hidden: learning what you cannot do is
		# how you learn what the other ninjas can.
		_prompt.modulate = Color(0.9, 1.0, 0.9) if interaction_target.can_use(self) 			else Color(0.62, 0.60, 0.58)
	else:
		_prompt.text = ""


## Attacks drive their own clip from begin_attack; reactions hold whatever pose
## they were caught in, since there is no hit-reaction clip yet. Everything else
## picks a locomotion clip from how fast the fighter is actually moving.
func _update_visual() -> void:
	if _visual == null:
		return
	match _state_id:
		FighterState.ATTACK:
			pass
		FighterState.HITSTUN, FighterState.KNOCKDOWN:
			_visual.hold()
		FighterState.CLIMB:
			_visual.release_attack()
			# No climb clip yet, so the walk cycle stands in, paced by how fast
			# the fighter is actually moving up the wall.
			_visual.play_locomotion(velocity.length() + 1.2, false)
		_:
			_visual.release_attack()
			_visual.play_locomotion(
				Vector2(velocity.x, velocity.z).length(), not is_on_floor())
	_update_prompt()


func _update_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_invulnerable = maxi(_invulnerable - 1, 0)
	_blockstun = maxi(_blockstun - 1, 0)

	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	_capture_buffered_presses()
	_decay_attack_buffer()
	_rampage_ticks = maxi(_rampage_ticks - 1, 0)
	for key in _power_cooldowns:
		_power_cooldowns[key] = maxf(_power_cooldowns[key] - delta, 0.0)
	_regenerate_stamina(delta)
	_update_flash()


func _transition_to(id: StringName) -> void:
	if not _states.has(id):
		return
	_state.exit()
	var previous := _state_id
	_state_id = id
	_state = _states[id]
	_state.enter(previous)


# --- Input ---

func get_input() -> InputFrame:
	if slot == null:
		return _empty_frame
	var frame := slot.get_frame()
	return frame if frame != null else _empty_frame


## Movement intent in world space, rotated into the camera's frame so that
## "up on the stick" always means "away from the viewer" regardless of where in
## the arena the fighter is standing.
func get_move_direction() -> Vector3:
	var intent := get_input().move
	if intent == Vector2.ZERO:
		return Vector3.ZERO

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3(intent.x, 0.0, -intent.y).normalized()

	var basis := camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	if forward.length_squared() < 0.0001:
		return Vector3.ZERO

	return (right.normalized() * intent.x + forward.normalized() * intent.y).normalized()


## Converts a world direction into the stick vector that would produce it.
## The inverse of get_move_direction, so a bot steers in world space and the
## camera-relative conversion stays in one place.
func to_input_space(world_direction: Vector3) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector2(world_direction.x, -world_direction.z).normalized()

	var basis := camera.global_transform.basis
	var forward := Vector3(-basis.z.x, 0.0, -basis.z.z)
	var right := Vector3(basis.x.x, 0.0, basis.x.z)
	if forward.length_squared() < 0.0001:
		return Vector2.ZERO

	var flat := Vector3(world_direction.x, 0.0, world_direction.z).normalized()
	return Vector2(flat.dot(right.normalized()), flat.dot(forward.normalized())).limit_length(1.0)


## Analog tilt, so a light push walks and a full push runs.
func get_move_strength() -> float:
	return minf(get_input().move.length(), 1.0)


func get_facing_direction() -> Vector3:
	return Basis(Vector3.UP, rotation.y) * Vector3.FORWARD


## Records presses without ageing the buffer. Safe to call during hitstop.
func _capture_buffered_presses() -> void:
	_attack_pressed_this_tick = false
	var input := get_input()
	if input.is_just_pressed(InputFrame.Action.JUMP):
		_jump_buffer = JUMP_BUFFER

	for action: InputFrame.Action in [
		InputFrame.Action.LIGHT, InputFrame.Action.HEAVY,
		InputFrame.Action.LAUNCHER, InputFrame.Action.GRAB,
		InputFrame.Action.SIGNATURE, InputFrame.Action.ULTIMATE,
	]:
		if input.is_just_pressed(action):
			_attack_buffer_action = action
			_attack_buffer_ticks = ATTACK_BUFFER_TICKS
			_attack_pressed_this_tick = true
			return


func _decay_attack_buffer() -> void:
	# Tracked with a flag rather than by comparing the counter to its maximum:
	# that comparison is also true on the tick after a press, so the buffer
	# would refuse to age and hold its action forever.
	if _attack_pressed_this_tick:
		return
	_attack_buffer_ticks = maxi(_attack_buffer_ticks - 1, 0)
	if _attack_buffer_ticks == 0:
		_attack_buffer_action = -1


func _peek_attack_buffer() -> int:
	return _attack_buffer_action if _attack_buffer_ticks > 0 else -1


func _clear_attack_buffer() -> void:
	_attack_buffer_action = -1
	_attack_buffer_ticks = 0


# --- Movement helpers used by the states ---

func apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	var scale := FALL_MULTIPLIER if velocity.y < 0.0 else 1.0
	velocity.y -= _gravity * scale * delta


## Releasing jump early clips the rise, giving a variable-height jump.
func apply_variable_jump_cut() -> void:
	if velocity.y > 0.0 and get_input().is_just_released(InputFrame.Action.JUMP):
		velocity.y *= JUMP_CUT


func apply_ground_acceleration(direction: Vector3, delta: float) -> void:
	var target := direction * character_def.get_max_speed() \
		* get_move_strength() * _speed_multiplier()
	var rate := character_def.get_acceleration() * delta
	velocity.x = move_toward(velocity.x, target.x, rate)
	velocity.z = move_toward(velocity.z, target.z, rate)


func apply_ground_friction(delta: float) -> void:
	var rate := character_def.get_ground_friction() * delta
	velocity.x = move_toward(velocity.x, 0.0, rate)
	velocity.z = move_toward(velocity.z, 0.0, rate)


func apply_air_acceleration(direction: Vector3, delta: float) -> void:
	var target := direction * character_def.get_max_speed() \
		* get_move_strength() * _speed_multiplier()
	var rate := character_def.get_acceleration() * character_def.get_air_control() * delta
	velocity.x = move_toward(velocity.x, target.x, rate)
	velocity.z = move_toward(velocity.z, target.z, rate)


## An attack takes your footing away. Committing is the whole point of a heavy.
func apply_attack_drift(delta: float) -> void:
	var rate := ATTACK_DRIFT_DRAG * delta
	velocity.x = move_toward(velocity.x, 0.0, rate)
	velocity.z = move_toward(velocity.z, 0.0, rate)


func apply_hitstun_drag(delta: float) -> void:
	var rate := HITSTUN_DRAG * delta
	velocity.x = move_toward(velocity.x, 0.0, rate)
	velocity.z = move_toward(velocity.z, 0.0, rate)


func apply_step(distance: float) -> void:
	if is_zero_approx(distance):
		return
	var step := get_facing_direction() * distance
	velocity.x += step.x
	velocity.z += step.z


func face_movement(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO:
		return
	var target := atan2(-direction.x, -direction.z)
	rotation.y = lerp_angle(rotation.y, target, character_def.get_turn_speed() * delta)


func snap_facing(direction: Vector3) -> void:
	if direction == Vector3.ZERO:
		return
	rotation.y = atan2(-direction.x, -direction.z)


# --- Requests: consume a buffered input if the fighter is allowed to act ---

## Returns true if a jump actually fired, and applies it. Ground jumps use
## coyote time; anything else spends one of the AGILITY-granted air jumps.
func request_jump() -> bool:
	if _jump_buffer <= 0.0:
		return false

	if is_on_floor() or _coyote > 0.0:
		_jump_buffer = 0.0
		_coyote = 0.0
		_air_jumps_left = character_def.get_extra_jumps()
		_air_dashes_left = 1
		velocity.y = _jump_velocity()
		return true

	if _air_jumps_left > 0:
		_air_jumps_left -= 1
		_jump_buffer = 0.0
		velocity.y = _jump_velocity() * AIR_JUMP_SCALE
		return true

	return false


## One air dash per airborne period, on top of the cooldown and the stamina
## cost, so dodging cannot be chained into free flight.
func request_dash() -> bool:
	if _dash_cooldown > 0.0:
		return false
	if not get_input().is_just_pressed(InputFrame.Action.DODGE):
		return false
	if not is_on_floor() and _air_dashes_left <= 0:
		return false
	if not spend_stamina(DODGE_STAMINA):
		return false
	if not is_on_floor():
		_air_dashes_left -= 1
	return true


## Starts a fresh attack (not a cancel). Grounded and airborne fighters draw
## from different halves of the moveset.
func request_attack() -> bool:
	if carried != null:
		return false  # hands full; throw it first
	var action := _peek_attack_buffer()
	if action == -1:
		return false

	var grounded := is_on_floor()
	var attack: AttackDef = null
	match action:
		InputFrame.Action.LIGHT:
			_light_chain_index = 0
			attack = move_set.light(0) if grounded else move_set.air_light
		InputFrame.Action.HEAVY:
			attack = move_set.heavy if grounded else move_set.air_heavy
		InputFrame.Action.LAUNCHER:
			attack = move_set.launcher if grounded else move_set.air_heavy
		InputFrame.Action.GRAB:
			attack = move_set.grab if grounded else null
		InputFrame.Action.SIGNATURE:
			attack = _affordable_power(character_def.signature)
		InputFrame.Action.ULTIMATE:
			attack = _affordable_power(character_def.ultimate)

	if attack == null:
		return false
	_clear_attack_buffer()
	pending_attack = attack
	_commit_power_cost(attack)
	return true


## A power the meter can pay for and whose cooldown has expired, or null. Not
## every character has powers built yet; theirs simply return nothing.
func _affordable_power(candidate: Power) -> Power:
	if candidate == null:
		return null
	if power < candidate.power_cost:
		return null
	if _power_cooldowns.get(candidate, 0.0) > 0.0:
		return null
	return candidate


## Charged on commit, not on connect: a whiffed special costs you the meter.
func _commit_power_cost(attack: AttackDef) -> void:
	var as_power := attack as Power
	if as_power == null:
		return
	power = maxf(power - as_power.power_cost, 0.0)
	_power_cooldowns[as_power] = as_power.cooldown_seconds


func activate_power(attack: AttackDef) -> void:
	var as_power := attack as Power
	if as_power != null:
		as_power.activate(self)


## Armour, not invulnerability: hits still land and still hurt, they just stop
## interrupting. Anything above the threshold breaks through.
func apply_rampage(ticks: int, armour: float, bonus: float) -> void:
	_rampage_ticks = maxi(_rampage_ticks, ticks)
	_rampage_armour = armour
	_rampage_bonus = bonus


func is_rampaging() -> bool:
	return _rampage_ticks > 0


## Called from AttackState once the cancel window is open. `connected` gates the
## confirms: whiffing a heavy costs you the full recovery. `ticks_since_window`
## says how long the window has been open, which is what makes rhythm scorable.
func consume_cancel(current: AttackDef, connected: bool,
		ticks_since_window: int) -> StringName:
	if current.cancel_requires_hit and not connected:
		return FighterState.STAY

	var action := _peek_attack_buffer()
	if action == -1 or not is_on_floor():
		return FighterState.STAY

	var attack: AttackDef = null
	match action:
		InputFrame.Action.LIGHT:
			if move_set.has_light_follow_up(_light_chain_index):
				_light_chain_index += 1
				attack = move_set.light(_light_chain_index)
		InputFrame.Action.HEAVY:
			if connected:
				attack = move_set.heavy
		InputFrame.Action.LAUNCHER:
			if connected:
				attack = move_set.launcher

	if attack == null:
		return FighterState.STAY

	_score_rhythm(current, ticks_since_window)
	_clear_attack_buffer()
	pending_attack = attack
	cancel_count += 1
	return FighterState.ATTACK


## Judges how close the press was to the moment this move became cancellable.
##
## The buffer is not aged during hitstop, so a freeze never counts against the
## player's timing -- which matters, because hitstop is exactly when the next
## press happens.
func _score_rhythm(current: AttackDef, ticks_since_window: int) -> void:
	var press_age := ATTACK_BUFFER_TICKS - _attack_buffer_ticks
	var offset := ticks_since_window - press_age
	var on_beat := absi(offset) <= current.rhythm_window_ticks

	_pending_on_beat = on_beat
	flow = mini(flow + 1, CombatMath.MAX_FLOW) if on_beat else 0


func consume_pending_on_beat() -> bool:
	var on_beat := _pending_on_beat
	_pending_on_beat = false
	return on_beat


## Called by AttackState as a move starts, so the fighter can set the damage
## multiplier and start the clip aligned to this move's own frame data.
func begin_attack(attack: AttackDef, on_beat: bool,
		startup_ticks: int, remainder_ticks: int) -> void:
	strike_scale = CombatMath.strike_scale(on_beat, flow)
	if is_rampaging():
		strike_scale *= 1.0 + _rampage_bonus
	if _visual == null or not attack.has_animation():
		return
	_visual.play_attack(
		attack.animation, attack.animation_start, attack.animation_impact,
		attack.animation_end, startup_ticks / 60.0, remainder_ticks / 60.0)


func end_attack_visual() -> void:
	if _visual != null:
		_visual.release_attack()


func request_block() -> bool:
	return is_on_floor() and stamina > 0.0 \
		and get_input().is_held(InputFrame.Action.BLOCK)


## Getting up early. Deliberately any of the two defensive buttons, because
## being on the floor is already punishing enough without a precise input.
func request_tech() -> bool:
	var input := get_input()
	return input.is_just_pressed(InputFrame.Action.DODGE) \
		or input.is_just_pressed(InputFrame.Action.JUMP)


func start_dash_cooldown() -> void:
	_dash_cooldown = character_def.get_dash_cooldown()


func end_attack_chain() -> void:
	_light_chain_index = 0


func on_landed() -> void:
	_air_jumps_left = character_def.get_extra_jumps()
	_air_dashes_left = 1


func _jump_velocity() -> float:
	return sqrt(2.0 * _gravity * character_def.get_jump_height())


# --- Combat ---

## Everything the hitbox overlaps this tick. A direct shape query rather than an
## Area3D, so the hitbox is live on exactly the ticks the frame data says.
func query_hitbox(attack: AttackDef) -> Array:
	_hitbox_shape.size = attack.hitbox_size
	_hitbox_query.transform = Transform3D(
		global_transform.basis,
		global_position + global_transform.basis * attack.hitbox_offset
	)

	var victims: Array = []
	for contact in get_world_3d().direct_space_state.intersect_shape(_hitbox_query, 8):
		var collider: Object = contact["collider"]

		var breakable := collider as Breakable
		if breakable != null:
			victims.append(breakable)
			continue

		var hurtbox := collider as Hurtbox
		if hurtbox == null:
			continue
		var other := hurtbox.fighter as Fighter
		if other != null and other != self:
			victims.append(other)
	return victims


## Resolves one connection. Returns whether it actually landed, which is what
## gates the confirm cancels.
## Resolves a connection against a fighter or a piece of breakable scenery.
func deal_hit(attack: AttackDef, target: Node) -> bool:
	var breakable := target as Breakable
	if breakable != null:
		return _hit_breakable(attack, breakable)

	var victim := target as Fighter
	if victim == null or victim.is_invulnerable():
		return false

	var contact: Vector3 = global_position.lerp(victim.global_position, 0.5) + Vector3.UP * 1.05
	var blocked := victim.is_blocking_against(global_position)
	var result := CombatMath.build_hit(attack, self, character_def, victim.character_def,
		get_facing_direction(), contact, blocked, strike_scale)
	result.on_beat = strike_scale > 1.0

	victim.take_hit(result)
	power = minf(power + attack.power_gain, max_power)
	apply_hitstop(result.hitstop_ticks)
	return true


func take_hit(result: HitResult) -> void:
	health = maxf(health - result.damage, 0.0)
	apply_hitstop(result.hitstop_ticks)
	_flash_ticks = HIT_FLASH_TICKS
	_spawn_feedback(result)
	damaged.emit(result)

	if result.blocked:
		# Blocked hits shove but never launch, and hold you in guard rather than
		# taking your state away.
		spend_stamina(result.damage * CombatMath.BLOCK_STAMINA_PER_DAMAGE)
		velocity.x = result.knockback.x
		velocity.z = result.knockback.z
		_blockstun = result.hitstun_ticks
	elif is_rampaging() and result.damage < _rampage_armour:
		# Absorbed: the damage lands, the interruption does not.
		velocity.x += result.knockback.x * 0.15
		velocity.z += result.knockback.z * 0.15
	else:
		if _state_id == FighterState.CLIMB:
			climbing = null
		velocity = result.knockback
		pending_hitstun = result.hitstun_ticks
		_knockdown_pending = result.knockback.length() >= CombatMath.KNOCKDOWN_SPEED
		_transition_to(FighterState.HITSTUN)

	# Reporting the knockout is as far as a fighter goes. Whether that costs a
	# stock, a respawn, or the match is the MatchManager's call.
	if health <= 0.0:
		defeated.emit()


## Scenery too tough for this fighter throws a dull spark and takes nothing, so
## the refusal reads as "not strong enough" rather than as a missed hit.
func _hit_breakable(attack: AttackDef, breakable: Breakable) -> bool:
	var amount := CombatMath.damage(attack, character_def) * strike_scale
	if breakable.take_attack(amount, self):
		HitSpark.spawn(get_tree().current_scene,
			breakable.global_position + Vector3.UP * 0.8, Color(1, 0.85, 0.55), amount)
		apply_hitstop(attack.ticks_hitstop)
		return true

	HitSpark.spawn(get_tree().current_scene,
		breakable.global_position + Vector3.UP * 0.8, Color(0.55, 0.58, 0.62), 4.0)
	apply_hitstop(3)
	return false


## Casts the chain finisher's fireball, if this move has one and the meter can
## pay for it. Running dry is not a failure state -- you simply get the kick.
func try_launch_fireball(attack: AttackDef) -> bool:
	if not attack.launches_fireball:
		return false
	if power < attack.fireball_power_cost:
		return false

	power -= attack.fireball_power_cost
	var facing := get_facing_direction()
	Fireball.cast(
		get_tree().current_scene,
		global_position + Vector3.UP * 1.15 + facing * 0.9,
		facing,
		attack.fireball_speed,
		attack.fireball_damage * CombatMath.offense(character_def.stat_strength),
		attack.fireball_knockback,
		self)
	return true


# --- Grabs ---
#
# A grab does not check whether the victim is blocking. That is the point of it:
# grab beats block, block beats strike, strike beats grab, and a guard that
# covered everything would make turtling strictly correct.

## Takes hold of a victim. Returns whether the grab caught them.
func seize(victim: Fighter) -> bool:
	if victim.is_invulnerable() or victim.is_eliminated:
		return false
	victim.velocity = Vector3.ZERO
	# Longer than any grab animation; the throw or an interrupt ends it.
	victim.pending_hitstun = 240
	victim._transition_to(FighterState.HITSTUN)
	apply_hitstop(4)
	return true


func hold_grabbed(victim: Fighter) -> void:
	if not is_instance_valid(victim):
		return
	victim.global_position = global_position + get_facing_direction() * 0.95
	victim.velocity = Vector3.ZERO


func throw_grabbed(victim: Fighter, attack: AttackDef) -> void:
	if not is_instance_valid(victim):
		return

	var radians := deg_to_rad(attack.grab_launch_angle)
	var direction := (get_facing_direction() * cos(radians) + Vector3.UP * sin(radians)).normalized()
	var scale := CombatMath.offense(character_def.stat_strength) \
		/ CombatMath.defense(victim.character_def.stat_toughness)

	var result := HitResult.new()
	result.attacker = self
	result.attack = attack
	result.damage = attack.grab_damage * CombatMath.offense(character_def.stat_strength)
	result.knockback = direction * attack.grab_throw_speed * scale
	result.hitstun_ticks = 34
	result.hitstop_ticks = 9
	result.position = victim.global_position + Vector3.UP

	victim.take_hit(result)
	power = minf(power + attack.power_gain, max_power)


## The grab was interrupted before the throw, so the victim simply gets up.
func release_grabbed(victim: Fighter) -> void:
	if is_instance_valid(victim) and victim.get_state_id() == FighterState.HITSTUN:
		victim._transition_to(FighterState.IDLE)


func _spawn_feedback(result: HitResult) -> void:
	var attacker := result.attacker as Fighter
	var color := Color(1, 0.9, 0.6)
	if result.blocked:
		color = Color(0.6, 0.8, 1.0)
	elif result.on_beat:
		color = Color(1.0, 0.95, 0.75)
	elif attacker != null and attacker.slot != null:
		color = attacker.slot.color.lerp(Color.WHITE, 0.5)

	var size := result.damage * (1.5 if result.on_beat else 1.0)
	HitSpark.spawn(get_tree().current_scene, result.position, color, size)

	var camera := get_viewport().get_camera_3d() as ArenaCamera
	if camera != null:
		var strength := clampf(result.damage / 26.0, 0.12, 1.0)
		camera.add_shake(strength * (1.35 if result.on_beat else 1.0))

	# Taking a hit buzzes hard and long; landing one is a short confirming tap.
	# On a controller-first game this carries as much of the impact as the shake.
	var felt := clampf(result.damage / 24.0, 0.18, 1.0)
	if not result.blocked and _visual != null:
		_visual.recoil(result.knockback, felt)
	_rumble(felt * 0.65, felt, 0.30 if result.on_beat else 0.22)
	var attacker_fighter := result.attacker as Fighter
	if attacker_fighter != null and attacker_fighter != self:
		attacker_fighter._rumble(felt * 0.35, felt * 0.5, 0.10)


func _rumble(weak: float, strong: float, duration: float) -> void:
	if slot != null and slot.source != null:
		slot.source.rumble(weak, strong, duration)


## Freezes both fighters for a moment on connect. With no animation to sell the
## hit, this and the knockback are where the impact actually comes from.
func apply_hitstop(ticks: int) -> void:
	_hitstop = maxi(_hitstop, ticks)


func grant_invulnerability(ticks: int) -> void:
	_invulnerable = maxi(_invulnerable, ticks)


func is_invulnerable() -> bool:
	return _invulnerable > 0


func is_in_blockstun() -> bool:
	return _blockstun > 0


func is_knockdown_pending() -> bool:
	return _knockdown_pending


func clear_knockdown() -> void:
	_knockdown_pending = false


## A block only covers the front. Getting flanked has to cost something, or
## holding guard would be strictly correct.
func is_blocking_against(attacker_position: Vector3) -> bool:
	if _state_id != FighterState.BLOCK:
		return false
	var to_attacker := attacker_position - global_position
	to_attacker.y = 0.0
	if to_attacker.length_squared() < 0.0001:
		return true
	return get_facing_direction().dot(to_attacker.normalized()) > 0.0


## True on the tick a high-speed knockback drove this fighter into a wall.
## Uses the speed recorded before the last move, because move_and_slide has
## already spent it by the time the collision is visible.
func check_wall_splat() -> bool:
	if _speed_before_move < CombatMath.WALL_SPLAT_SPEED:
		return false
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if absf(normal.y) < 0.5:
			# Peel off the wall so the victim is juggle-able rather than pinned,
			# and cancel the pending knockdown: any hit hard enough to splat is
			# also hard enough to knock down, and a splat that just put the
			# victim on the floor would be a worse outcome than a normal hit.
			velocity = normal * _speed_before_move * 0.28 + Vector3.UP * 3.5
			_knockdown_pending = false
			return true
	return false


func spend_stamina(amount: float) -> bool:
	if stamina < amount:
		return false
	stamina -= amount
	_stamina_delay = STAMINA_REGEN_DELAY
	return true


func _regenerate_stamina(delta: float) -> void:
	if _stamina_delay > 0.0:
		_stamina_delay -= delta
		return
	stamina = minf(stamina + STAMINA_REGEN_PER_SECOND * delta, max_stamina)


func _update_flash() -> void:
	if _visual == null:
		return
	if _flash_ticks > 0:
		_flash_ticks -= 1
	_visual.set_hit_flash(float(_flash_ticks) / float(HIT_FLASH_TICKS))


## Placeholder until there is a knockdown clip: the model is tipped over rather
## than animated onto the floor.
func set_downed(downed: bool) -> void:
	if _visual == null:
		return
	_visual.rotation.x = -1.35 if downed else 0.0
	_visual.position.y = -0.42 if downed else 0.0


# --- Match plumbing ---

## Swaps which ninja this seat is playing, in place. Respawning the node instead
## would mean re-registering with the camera, the HUD and the match for what is
## really just a different stat block.
func set_character(definition: CharacterDef) -> void:
	character_def = definition
	move_set = definition.move_set if definition.move_set != null else DEFAULT_MOVE_SET
	max_health = definition.get_max_health()
	max_power = definition.get_max_power()
	max_stamina = definition.get_max_stamina()
	health = max_health
	power = 0.0
	stamina = max_stamina
	_air_jumps_left = definition.get_extra_jumps()
	_power_cooldowns.clear()
	_apply_presentation()


## Call this before adding the fighter to the tree -- _ready() consumes the
## definition to build the state machine and the coloured presentation.
func setup(player_slot: PlayerSlot, definition: CharacterDef, spawn: Vector3) -> void:
	slot = player_slot
	character_def = definition
	spawn_point = spawn
	position = spawn


func respawn() -> void:
	if carried != null:
		carried.release()
		carried = null
	climbing = null
	global_position = spawn_point
	velocity = Vector3.ZERO
	health = max_health
	stamina = max_stamina
	_hitstop = 0
	_blockstun = 0
	_knockdown_pending = false
	cancel_count = 0
	attacks_started = 0
	flow = 0
	strike_scale = 1.0
	_pending_on_beat = false
	_rampage_ticks = 0
	# A fresh life should not inherit the last one's cooldowns.
	_power_cooldowns.clear()
	if slot != null and slot.source != null:
		slot.source.stop_rumble()
	# Drop queued intent as well as state: a fighter should not come back and
	# immediately act on a button pressed before it went down.
	_clear_attack_buffer()
	_jump_buffer = 0.0
	_coyote = 0.0
	_invulnerable = 0
	set_downed(false)
	_transition_to(FighterState.IDLE)


## Taken out of the match: hidden and frozen, but kept in the tree so the HUD
## and the match rules can still read its slot.
func eliminate() -> void:
	if is_eliminated:
		return
	is_eliminated = true
	if carried != null:
		carried.release()
		carried = null
	climbing = null
	velocity = Vector3.ZERO
	health = 0.0
	hide()
	set_physics_process(false)
	if slot != null and slot.source != null:
		slot.source.stop_rumble()


## Leaving the match entirely -- a bot being removed from the bench. Unlike
## eliminate(), this fighter is about to be freed, so anything it is holding on
## to has to be handed back first: a crate it is carrying, and, by way of the
## current state's exit(), anyone it has in a grab. Otherwise removing a bot
## mid-throw would leave its victim frozen in hitstun with nobody to release it.
func vacate() -> void:
	if carried != null:
		carried.release()
		carried = null
	climbing = null
	_state.exit()
	set_physics_process(false)
	if slot != null and slot.source != null:
		slot.source.stop_rumble()
	remove_from_group(&"fighters")


## Brought back for a rematch.
func restore() -> void:
	is_eliminated = false
	show()
	set_physics_process(true)
	respawn()


func get_state_id() -> StringName:
	return _state_id


func get_debug_line() -> String:
	return "%s %-10s %-9s hp %5.1f  pw %5.1f  st %5.1f  flow %d%s" % [
		slot.get_label() if slot != null else "--",
		character_def.display_name,
		_state_id,
		health,
		power,
		stamina,
		flow,
		"  RAMPAGE" if is_rampaging() else "",
	]
