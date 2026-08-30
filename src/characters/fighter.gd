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
	_hitbox_query.collision_mask = Layers.HURTBOX
	_hitbox_query.collide_with_areas = true
	_hitbox_query.collide_with_bodies = false

	_build_states()
	_apply_presentation()


func _build_states() -> void:
	var states: Array[FighterState] = [
		IdleState.new(), RunState.new(), AirState.new(), DashState.new(),
		AttackState.new(), HitstunState.new(), KnockdownState.new(), BlockState.new(),
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

	var next := _state.physics_update(delta)
	if next != FighterState.STAY:
		# Note the absence of a "different state" guard: cancelling one attack
		# into another is a transition from ATTACK to ATTACK, and suppressing
		# self-transitions would silently swallow every chain and confirm.
		# States already return STAY to mean "no change".
		_transition_to(next)

	_speed_before_move = velocity.length()
	move_and_slide()
	_update_visual()

	if global_position.y < FALL_OUT_HEIGHT:
		respawn()


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
		_:
			_visual.release_attack()
			_visual.play_locomotion(
				Vector2(velocity.x, velocity.z).length(), not is_on_floor())


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
		InputFrame.Action.LIGHT, InputFrame.Action.HEAVY, InputFrame.Action.LAUNCHER
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
	var target := direction * character_def.get_max_speed() * get_move_strength()
	var rate := character_def.get_acceleration() * delta
	velocity.x = move_toward(velocity.x, target.x, rate)
	velocity.z = move_toward(velocity.z, target.z, rate)


func apply_ground_friction(delta: float) -> void:
	var rate := character_def.get_ground_friction() * delta
	velocity.x = move_toward(velocity.x, 0.0, rate)
	velocity.z = move_toward(velocity.z, 0.0, rate)


func apply_air_acceleration(direction: Vector3, delta: float) -> void:
	var target := direction * character_def.get_max_speed() * get_move_strength()
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

	if attack == null:
		return false
	_clear_attack_buffer()
	pending_attack = attack
	return true


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
		var hurtbox := contact["collider"] as Hurtbox
		if hurtbox == null:
			continue
		var other := hurtbox.fighter as Fighter
		if other != null and other != self:
			victims.append(other)
	return victims


## Resolves one connection. Returns whether it actually landed, which is what
## gates the confirm cancels.
func deal_hit(attack: AttackDef, victim: Fighter) -> bool:
	if victim.is_invulnerable():
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
	else:
		velocity = result.knockback
		pending_hitstun = result.hitstun_ticks
		_knockdown_pending = result.knockback.length() >= CombatMath.KNOCKDOWN_SPEED
		_transition_to(FighterState.HITSTUN)

	if health <= 0.0:
		defeated.emit()
		respawn()


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

## Call this before adding the fighter to the tree -- _ready() consumes the
## definition to build the state machine and the coloured presentation.
func setup(player_slot: PlayerSlot, definition: CharacterDef, spawn: Vector3) -> void:
	slot = player_slot
	character_def = definition
	spawn_point = spawn
	position = spawn


func respawn() -> void:
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


func get_state_id() -> StringName:
	return _state_id


func get_debug_line() -> String:
	return "%s %-10s %-9s hp %5.1f  pw %5.1f  st %5.1f  flow %d" % [
		slot.get_label() if slot != null else "--",
		character_def.display_name,
		_state_id,
		health,
		power,
		stamina,
		flow,
	]
