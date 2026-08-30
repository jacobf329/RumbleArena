## Headless verification of the M1 systems.
##
## Runs the real main scene with scripted input sources, so this exercises the
## same code path a player does rather than a parallel test-only one. Exits
## non-zero if any check fails.
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

## An open lane of arena floor with no geometry in it, so movement tests measure
## movement rather than how quickly a fighter finds a wall.
const CLEAR_LANE_Z := 13.0

var _failures: Array[String] = []
var _checks := 0
var _main: Node3D
var _camera: ArenaCamera


func _ready() -> void:
	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	_camera = _main.get_node("ArenaCamera")
	PlayerManager.join_enabled = false
	await _run()
	_report()


func _run() -> void:
	var kurogane := await _join(0)   # STR 5 / SPD 2 / AGI 2 -- no double jump
	var yamabuki := await _join(3)   # AGI 5 / SPD 3 -- double jump

	_check(kurogane != null, "fighter spawned for slot 0")
	_check(yamabuki != null, "fighter spawned for slot 3")
	if kurogane == null or yamabuki == null:
		return

	_check(kurogane.character_def.display_name == "Kurogane", "slot 0 got Kurogane")
	_check(yamabuki.character_def.display_name == "Yamabuki", "slot 3 got Yamabuki")

	await _ticks(40)
	_check(kurogane.is_on_floor(), "fighter settles onto the arena floor")

	_test_scene_orientation()
	await _test_movement(kurogane)
	await _test_jump_arc(kurogane)
	await _test_variable_jump_height(yamabuki)
	await _test_double_jump_is_agility_gated(kurogane, yamabuki)
	await _test_dash(yamabuki)
	await _test_camera_framing(kurogane, yamabuki)
	await _test_camera_smoothing_is_asymmetric(kurogane, yamabuki)
	await _test_camera_has_clear_view(kurogane, yamabuki)
	await _test_fall_out_respawns(kurogane)


## Hand-authored Transform3D literals in a .tscn are row-major while basis.x/y/z
## are columns, so a matrix computed as columns silently becomes its own inverse.
## That bug pointed the sun at the sky and sloped both ramps the wrong way, and
## nothing but a screenshot would have caught it -- hence these checks.
func _test_scene_orientation() -> void:
	var sun: DirectionalLight3D = _main.get_node("Sun")
	var light_direction := -sun.global_transform.basis.z
	_check(light_direction.y < -0.5,
		"the sun shines downward (direction y = %.2f)" % light_direction.y)

	# Each ramp must rise toward the centre platform it feeds. The two ramps are
	# mirrored, so uphill is derived from the surface normal rather than assumed
	# to lie along a particular local axis: a surface whose normal leans toward
	# +Z rises toward -Z.
	for ramp_name: String in ["RampSouth", "RampNorth"]:
		var ramp: Node3D = _main.get_node("Arena/Geometry/" + ramp_name)
		var normal := ramp.global_transform.basis.y
		_check(normal.y > 0.5, "%s has an upward-facing surface" % ramp_name)

		var lean := Vector3(normal.x, 0.0, normal.z)
		_check(lean.length() > 0.1, "%s is actually sloped, not flat" % ramp_name)

		var uphill := -lean.normalized()
		var toward_centre := Vector3(-ramp.global_position.x, 0.0, -ramp.global_position.z)
		_check(uphill.dot(toward_centre.normalized()) > 0.9,
			"%s slopes up toward the centre platform" % ramp_name)


# --- Movement ---

func _test_movement(fighter: Fighter) -> void:
	var source := _source(fighter)
	await _place(fighter, Vector3(-8, 0.5, CLEAR_LANE_Z))
	var start := fighter.global_position

	source.move = Vector2(1, 0)
	await _ticks(45)

	var travelled := fighter.global_position.distance_to(start)
	_check(travelled > 4.0, "holding the stick moves the fighter (moved %.1f)" % travelled)

	var speed := Vector2(fighter.velocity.x, fighter.velocity.z).length()
	var expected: float = fighter.character_def.get_max_speed()
	_check(absf(speed - expected) < 1.0,
		"reaches its stat-derived top speed (%.1f, expected ~%.1f)" % [speed, expected])
	_check(fighter.get_state_id() == FighterState.RUN, "is in the run state while moving")

	source.move = Vector2.ZERO
	await _ticks(45)
	_check(fighter.get_state_id() == FighterState.IDLE, "returns to idle when the stick centres")


# --- Jumping ---

func _test_jump_arc(fighter: Fighter) -> void:
	await _place(fighter, Vector3(-8, 0.5, CLEAR_LANE_Z))
	var height := await _measure_jump(fighter, false)
	var expected: float = fighter.character_def.get_jump_height()

	_check(absf(height - expected) < 0.5,
		"a held jump reaches its AGILITY-derived height (%.2f, expected ~%.2f)"
			% [height, expected])
	_check(fighter.is_on_floor(), "the fighter comes back down and lands")


## Releasing the button early clips the rise. This is the feel feature that
## makes a jump controllable rather than a fixed animation.
func _test_variable_jump_height(fighter: Fighter) -> void:
	await _place(fighter, Vector3(4, 0.5, CLEAR_LANE_Z))
	var tapped := await _measure_tapped_jump(fighter)
	await _place(fighter, Vector3(4, 0.5, CLEAR_LANE_Z))
	var held := await _measure_jump(fighter, false)

	_check(tapped < held - 0.8,
		"a tapped jump is meaningfully shorter than a held one (%.2f vs %.2f)"
			% [tapped, held])


## The first permission check a player meets: AGILITY 3+ buys a second jump.
## Measured within each character so the comparison isolates the second press.
func _test_double_jump_is_agility_gated(low_agility: Fighter, high_agility: Fighter) -> void:
	_check(low_agility.character_def.get_extra_jumps() == 0,
		"Kurogane (AGI 2) is denied a double jump")
	_check(high_agility.character_def.get_extra_jumps() == 1,
		"Yamabuki (AGI 5) is granted a double jump")

	await _place(high_agility, Vector3(0, 0.5, CLEAR_LANE_Z))
	var high_single := await _measure_jump(high_agility, false)
	await _place(high_agility, Vector3(0, 0.5, CLEAR_LANE_Z))
	var high_double := await _measure_jump(high_agility, true)
	_check(high_double > high_single + 1.0,
		"Yamabuki's second press buys real height (%.2f -> %.2f)" % [high_single, high_double])

	await _place(low_agility, Vector3(-8, 0.5, CLEAR_LANE_Z))
	var low_single := await _measure_jump(low_agility, false)
	await _place(low_agility, Vector3(-8, 0.5, CLEAR_LANE_Z))
	var low_double := await _measure_jump(low_agility, true)
	_check(absf(low_double - low_single) < 0.3,
		"Kurogane's second press buys nothing (%.2f -> %.2f)" % [low_single, low_double])


## Holds jump through the apex the way a player does, optionally releasing and
## pressing again just past the peak to spend an air jump.
func _measure_jump(fighter: Fighter, use_second_jump: bool) -> float:
	var source := _source(fighter)
	var ground_y := fighter.global_position.y
	var peak := ground_y

	source.hold(InputFrame.Action.JUMP, true)
	for i in 170:
		await get_tree().physics_frame
		peak = maxf(peak, fighter.global_position.y)
		match i:
			36: source.hold(InputFrame.Action.JUMP, false)
			39: source.hold(InputFrame.Action.JUMP, use_second_jump)
			48: source.hold(InputFrame.Action.JUMP, false)
		if fighter.is_on_floor() and i > 60:
			break
	source.release_all()
	await _ticks(10)
	return peak - ground_y


func _measure_tapped_jump(fighter: Fighter) -> float:
	var source := _source(fighter)
	var ground_y := fighter.global_position.y
	var peak := ground_y

	source.hold(InputFrame.Action.JUMP, true)
	await _ticks(2)
	source.hold(InputFrame.Action.JUMP, false)
	for i in 170:
		await get_tree().physics_frame
		peak = maxf(peak, fighter.global_position.y)
		if fighter.is_on_floor() and i > 10:
			break
	source.release_all()
	await _ticks(10)
	return peak - ground_y


# --- Dash ---

func _test_dash(fighter: Fighter) -> void:
	var source := _source(fighter)
	await _place(fighter, Vector3(-10, 0.5, -11))

	source.move = Vector2(1, 0)
	await _ticks(5)
	var start := fighter.global_position

	await _press(source, InputFrame.Action.DODGE)
	_check(fighter.get_state_id() == FighterState.DASH, "dodge enters the dash state")

	await _ticks(10)
	var covered := fighter.global_position.distance_to(start)
	_check(covered > 1.5, "the dash covers ground quickly (%.1f units)" % covered)

	await _ticks(6)
	_check(fighter.get_state_id() != FighterState.DASH, "the dash ends on its own")

	# The cooldown is what stops dash-spam from becoming free flight. It starts
	# when the dash starts, so it must still be running shortly after the dash
	# itself has ended -- that overlap is the whole point.
	await _press(source, InputFrame.Action.DODGE)
	_check(fighter.get_state_id() != FighterState.DASH,
		"a second dash is refused while the cooldown is still running")

	var cooldown: float = fighter.character_def.get_dash_cooldown()
	await _ticks(int(cooldown * 60.0) + 10)
	await _press(source, InputFrame.Action.DODGE)
	_check(fighter.get_state_id() == FighterState.DASH,
		"the dash is available again once the cooldown expires")

	source.move = Vector2.ZERO
	source.release_all()
	await _ticks(60)


# --- Camera ---

func _test_camera_framing(a: Fighter, b: Fighter) -> void:
	await _hold_apart(a, b, 2.0)
	var close := _camera.get_distance()

	await _hold_apart(a, b, 13.0)
	var far := _camera.get_distance()

	_check(far > close, "the camera pulls back as fighters separate (%.1f -> %.1f)" % [close, far])
	_check(close >= _camera.min_distance - 0.01, "framing respects the minimum distance")
	_check(far <= _camera.max_distance + 0.01, "framing respects the maximum distance")

	var focus := _camera.get_focus()
	var midpoint := (a.global_position + b.global_position) * 0.5
	_check(focus.distance_to(midpoint) < 2.0,
		"the camera focuses between the fighters (off by %.2f)" % focus.distance_to(midpoint))


## Zoom out fast, zoom in slow. Snapping in on a KO and back out is nauseating,
## so this asymmetry is a deliberate feel decision worth locking down.
func _test_camera_smoothing_is_asymmetric(a: Fighter, b: Fighter) -> void:
	const SETTLE := 20

	await _hold_apart(a, b, 2.0)
	var close := _camera.get_distance()
	_set_apart(a, b, 13.0)
	await _ticks(SETTLE)
	var after_retreat := _camera.get_distance()

	await _hold_apart(a, b, 13.0)
	var far := _camera.get_distance()
	_set_apart(a, b, 2.0)
	await _ticks(SETTLE)
	var after_return := _camera.get_distance()

	var retreat_progress := (after_retreat - close) / maxf(far - close, 0.001)
	var return_progress := (far - after_return) / maxf(far - close, 0.001)

	_check(retreat_progress > return_progress,
		"the camera retreats faster than it returns (%.0f%% out vs %.0f%% in over %d ticks)"
			% [retreat_progress * 100.0, return_progress * 100.0, SETTLE])


## Fighters pressed against an arena edge push the camera outside the arena
## looking back in. Tall perimeter walls then stand directly between the camera
## and the fight -- which is how the original 7-unit walls were caught, and why
## the boundary is now collision-only.
func _test_camera_has_clear_view(a: Fighter, b: Fighter) -> void:
	for i in 240:
		a.global_position = Vector3(-2.5, 0.3, 13.5)
		b.global_position = Vector3(2.5, 0.3, 13.5)
		a.velocity = Vector3.ZERO
		b.velocity = Vector3.ZERO
		await get_tree().physics_frame

	var space := a.get_world_3d().direct_space_state
	for fighter: Fighter in [a, b]:
		var query := PhysicsRayQueryParameters3D.create(
			_camera.global_position, fighter.global_position + Vector3.UP * 1.2)
		query.collision_mask = Arena.Layer.WORLD
		var hit := space.intersect_ray(query)
		_check(hit.is_empty(), "the camera can see %s pressed against the arena edge%s"
			% [fighter.character_def.display_name,
				"" if hit.is_empty() else " (blocked by %s)" % hit["collider"].name])


func _test_fall_out_respawns(fighter: Fighter) -> void:
	var spawn := fighter.spawn_point
	fighter.global_position = Vector3(0, -30, 0)
	await _ticks(5)
	_check(fighter.global_position.distance_to(spawn) < 1.0,
		"falling out of the arena puts the fighter back on its spawn")


# --- Harness plumbing ---

func _join(slot_index: int) -> Fighter:
	var slot: PlayerSlot = PlayerManager.slots[slot_index]
	slot.source = ScriptedInputSource.new()
	PlayerManager.player_joined.emit(slot)
	await get_tree().physics_frame
	return slot.fighter as Fighter


func _source(fighter: Fighter) -> ScriptedInputSource:
	return fighter.slot.source as ScriptedInputSource


func _place(fighter: Fighter, position: Vector3) -> void:
	_source(fighter).release_all()
	_source(fighter).move = Vector2.ZERO
	fighter.global_position = position
	fighter.velocity = Vector3.ZERO
	await _ticks(30)


func _set_apart(a: Fighter, b: Fighter, half_gap: float) -> void:
	a.global_position = Vector3(-half_gap, 1.0, 0)
	b.global_position = Vector3(half_gap, 1.0, 0)
	a.velocity = Vector3.ZERO
	b.velocity = Vector3.ZERO


## Pins the pair in place long enough for the camera to fully settle, so a
## measurement reads the steady state and not a moment mid-lerp.
func _hold_apart(a: Fighter, b: Fighter, half_gap: float) -> void:
	for i in 240:
		_set_apart(a, b, half_gap)
		await get_tree().physics_frame


## Holds an action for two ticks then releases, producing exactly one
## just-pressed edge that the fighter is guaranteed to observe.
func _press(source: ScriptedInputSource, action: InputFrame.Action) -> void:
	source.hold(action, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(action, false)
	await get_tree().physics_frame


func _ticks(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if condition:
		print("  PASS  %s" % description)
	else:
		print("  FAIL  %s" % description)
		_failures.append(description)


func _report() -> void:
	print("")
	print("M1 smoke test: %d checks, %d failed" % [_checks, _failures.size()])
	for failure in _failures:
		print("  failed: %s" % failure)
	get_tree().quit(0 if _failures.is_empty() else 1)
