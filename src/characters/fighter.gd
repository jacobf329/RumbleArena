## A player-controlled ninja.
##
## Reads intent only from an InputFrame -- never from Input directly. All feel
## constants that vary per character come from CharacterDef, so this class stays
## character-agnostic (GAME_DESIGN.md section 9).
class_name Fighter
extends CharacterBody3D

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

@export var character_def: CharacterDef

var slot: PlayerSlot
var spawn_point := Vector3.ZERO

var health: float = 100.0
var power: float = 0.0

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

@onready var _body_mesh: MeshInstance3D = $Visual/Body
@onready var _accent_mesh: MeshInstance3D = $Visual/Accent
@onready var _nameplate: Label3D = $Nameplate


func _ready() -> void:
	if character_def == null:
		character_def = CharacterDef.new()
	_gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 24.0))
	health = character_def.get_max_health()
	_air_jumps_left = character_def.get_extra_jumps()
	_air_dashes_left = 1

	_build_states()
	_apply_presentation()


func _build_states() -> void:
	for state: FighterState in [IdleState.new(), RunState.new(), AirState.new(), DashState.new()]:
		state.setup(self)
		_states[state.get_id()] = state
	_state = _states[FighterState.IDLE]
	_state.enter(FighterState.IDLE)


## Player identity beats character identity: the body wears the slot colour so
## "which one am I" is answered by silhouette, and the character shows up as an
## accent stripe. Pillar P3.
func _apply_presentation() -> void:
	var slot_color: Color = slot.color if slot != null else Color.WHITE
	_body_mesh.material_override = _flat_material(slot_color)
	_accent_mesh.material_override = _flat_material(character_def.body_color)

	_nameplate.text = "%s  %s" % [
		slot.get_label() if slot != null else "--",
		character_def.display_name,
	]
	_nameplate.modulate = slot_color


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.65
	return material


func _physics_process(delta: float) -> void:
	_update_timers(delta)

	var next := _state.physics_update(delta)
	if next != FighterState.STAY and next != _state_id:
		_transition_to(next)

	move_and_slide()

	if global_position.y < FALL_OUT_HEIGHT:
		respawn()


func _update_timers(delta: float) -> void:
	_dash_cooldown = maxf(_dash_cooldown - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)

	if is_on_floor():
		_coyote = COYOTE_TIME
	else:
		_coyote = maxf(_coyote - delta, 0.0)

	if get_input().is_just_pressed(InputFrame.Action.JUMP):
		_jump_buffer = JUMP_BUFFER


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


## One air dash per airborne period, on top of the cooldown, so dashing cannot
## be chained into free flight.
func request_dash() -> bool:
	if _dash_cooldown > 0.0:
		return false
	if not get_input().is_just_pressed(InputFrame.Action.DODGE):
		return false
	if not is_on_floor():
		if _air_dashes_left <= 0:
			return false
		_air_dashes_left -= 1
	return true


func start_dash_cooldown() -> void:
	_dash_cooldown = character_def.get_dash_cooldown()


func on_landed() -> void:
	_air_jumps_left = character_def.get_extra_jumps()
	_air_dashes_left = 1


func _jump_velocity() -> float:
	return sqrt(2.0 * _gravity * character_def.get_jump_height())


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
	_transition_to(FighterState.IDLE)


func get_state_id() -> StringName:
	return _state_id


func get_debug_line() -> String:
	var planar := Vector2(velocity.x, velocity.z).length()
	return "%s %-10s %-5s spd %4.1f  air-jump %d  dash %.2f" % [
		slot.get_label() if slot != null else "--",
		character_def.display_name,
		_state_id,
		planar,
		_air_jumps_left,
		_dash_cooldown,
	]
