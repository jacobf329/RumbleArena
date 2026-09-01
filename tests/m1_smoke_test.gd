## Headless verification of the M1 movement, input and camera systems.
extends TestHarness

## An open lane of arena floor with no geometry in it, so movement tests measure
## movement rather than how quickly a fighter finds a wall.
const CLEAR_LANE_Z := 13.0


func _init() -> void:
	test_name = "M1 smoke test"


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
	await _test_a_fight_at_the_arena_edge_stays_framed(kurogane, yamabuki)
	await _test_fall_out_respawns(kurogane)

	_section("Real device input")
	_test_every_action_is_bound()
	await _test_gamepad_reads_its_device()
	await _test_keyboard_drives_a_fighter()


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
## Nobody is clipped when the fight is jammed into a corner.
##
## Every other camera check stages fights in the middle of the room, where the
## focus is free to sit exactly between the fighters. Out here it is clamped to
## the camera bounds while the fighters are not, so the frame is centred somewhere
## they are not standing -- the one case where the framing has to work for a
## centre it did not choose. Padding is dropped for the duration to take away the
## slack that would otherwise make this pass no matter what.
##
## Deliberately a broad property check: it does not isolate any particular
## framing mistake, because at the scale where the clamp engages, min_distance
## and head_room dominate anything the clamp does. It is here to catch a future
## change that makes edge framing much worse, not to guard one line.
func _test_a_fight_at_the_arena_edge_stays_framed(a: Fighter, b: Fighter) -> void:
	# Hard into the corner. The floor reaches +-16 and the camera bounds stop at
	# +-14, so a midpoint out here is genuinely outside them -- which is the only
	# situation where the clamped focus and the true centre come apart at all.
	await _place(a, Vector3(-15.5, 0.3, 15.5))
	await _place(b, Vector3(-13.0, 0.3, 15.5))

	var original_padding: float = _camera.padding
	_camera.padding = 0.2
	await _ticks(150)

	var focus := _camera.get_focus()
	var midpoint := (a.global_position + b.global_position) * 0.5
	_check(focus.distance_to(midpoint) > 0.5,
		"the focus really is clamped away from the fighters (%.1f m)"
			% focus.distance_to(midpoint))

	for fighter: Fighter in [a, b]:
		_check(_within_frame(fighter),
			"%s is still on screen at the arena edge" % fighter.character_def.display_name)

	_camera.padding = original_padding
	await _ticks(60)


## Whether a fighter, nameplate and all, sits inside the frustum. Measured on
## the camera's own axes rather than by unprojecting to pixels, because the
## headless viewport is not the shape the game is played on.
func _within_frame(fighter: Fighter) -> bool:
	var half_height: float = _camera.get_distance() * tan(deg_to_rad(_camera.fov) * 0.5)
	var half_width: float = half_height * (16.0 / 9.0)
	var offset: Vector3 = (fighter.global_position + Vector3.UP * 2.7) - _camera.get_focus()
	return absf(offset.dot(_camera.global_transform.basis.x)) <= half_width \
		and absf(offset.dot(_camera.global_transform.basis.y)) <= half_height


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
		query.collision_mask = Layers.WORLD
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


# --- Real device input ---

## Every test above drives a ScriptedInputSource, which bypasses the keyboard
## and gamepad classes entirely -- so the one path a human actually uses is the
## one path nothing else covers. A missing binding would ship as "the launcher
## button does nothing" and no other test would notice.
func _test_every_action_is_bound() -> void:
	for action in InputFrame.Action.values():
		var name: String = InputFrame.Action.keys()[action]
		_check(KeyboardInputSource.BINDINGS.has(action),
			"keyboard binds %s" % name)
		_check(GamepadInputSource.BUTTON_BINDINGS.has(action)
				or GamepadInputSource.TRIGGER_BINDINGS.has(action),
			"gamepad binds %s" % name)


## The gamepad is the primary interface, so its mapping gets checked against
## simulated device events rather than trusted. A pad cannot be faked into
## Input.get_connected_joypads() headlessly, so the source is read directly --
## which is the part that carries the mapping, the deadzone and the d-pad.
func _test_gamepad_reads_its_device() -> void:
	const DEVICE := 0
	var pad := GamepadInputSource.new(DEVICE)

	for pair: Array in [
		[JOY_BUTTON_A, InputFrame.Action.JUMP, "A jumps"],
		[JOY_BUTTON_X, InputFrame.Action.LIGHT, "X is light"],
		[JOY_BUTTON_Y, InputFrame.Action.HEAVY, "Y is heavy"],
		[JOY_BUTTON_B, InputFrame.Action.GRAB, "B grabs"],
		[JOY_BUTTON_B, InputFrame.Action.INTERACT, "B also interacts"],
		[JOY_BUTTON_LEFT_SHOULDER, InputFrame.Action.BLOCK, "LB blocks"],
		[JOY_BUTTON_RIGHT_SHOULDER, InputFrame.Action.LAUNCHER, "RB launches"],
		[JOY_BUTTON_RIGHT_STICK, InputFrame.Action.ULTIMATE, "R3 is the ultimate"],
	]:
		await _hold_pad_button(DEVICE, pair[0])
		var frame := _read_pad(pad)
		_check(frame.is_held(pair[1]), pair[2])
		await _release_pad_button(DEVICE, pair[0])

	# Join uses the same A that jumps, so a pad claims a seat with the button a
	# player will already be pressing.
	await _hold_pad_button(DEVICE, JOY_BUTTON_A)
	_check(GamepadInputSource.is_join_requested(DEVICE), "A claims a free seat")
	await _release_pad_button(DEVICE, JOY_BUTTON_A)

	await _move_pad_axis(DEVICE, JOY_AXIS_LEFT_X, 0.9)
	var pushed := _read_pad(pad)
	_check(pushed.move.x > 0.5, "pushing the stick right moves right (%.2f)" % pushed.move.x)

	await _move_pad_axis(DEVICE, JOY_AXIS_LEFT_X, 0.1)
	var drift := _read_pad(pad)
	_check(drift.move == Vector2.ZERO, "stick drift inside the deadzone is ignored")
	await _move_pad_axis(DEVICE, JOY_AXIS_LEFT_X, 0.0)

	# Godot reports stick up as negative; the frame's convention is up-positive.
	await _move_pad_axis(DEVICE, JOY_AXIS_LEFT_Y, -0.9)
	var forward := _read_pad(pad)
	_check(forward.move.y > 0.5, "stick up reads as forward (%.2f)" % forward.move.y)
	await _move_pad_axis(DEVICE, JOY_AXIS_LEFT_Y, 0.0)

	await _hold_pad_button(DEVICE, JOY_BUTTON_DPAD_LEFT)
	var dpad := _read_pad(pad)
	_check(dpad.move.x < -0.5, "the d-pad moves too (%.2f)" % dpad.move.x)
	await _release_pad_button(DEVICE, JOY_BUTTON_DPAD_LEFT)

	await _move_pad_axis(DEVICE, JOY_AXIS_TRIGGER_LEFT, 0.9)
	var trigger := _read_pad(pad)
	_check(trigger.is_held(InputFrame.Action.DODGE), "the left trigger dodges")
	await _move_pad_axis(DEVICE, JOY_AXIS_TRIGGER_LEFT, 0.0)


func _read_pad(pad: GamepadInputSource) -> InputFrame:
	pad.frame.begin_frame()
	pad._read(pad.frame)
	return pad.frame


func _hold_pad_button(device: int, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().physics_frame


func _release_pad_button(device: int, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = device
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().physics_frame


func _move_pad_axis(device: int, axis: JoyAxis, value: float) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	Input.parse_input_event(event)
	await get_tree().physics_frame


## Presses real keys through the input singleton and follows them all the way
## to a fighter moving: join, device assignment, InputFrame, state machine.
func _test_keyboard_drives_a_fighter() -> void:
	PlayerManager.join_enabled = true
	var slot := PlayerManager.get_free_slot()
	_check(slot != null, "a seat is free for the keyboard player")
	if slot == null:
		return

	await _hold_key(KEY_SPACE, 3)
	# Space joins and also jumps, so it has to be let go before anything is
	# measured on the ground.
	await _release_key(KEY_SPACE)
	await _ticks(3)
	_check(slot.is_active(), "pressing Space joins the keyboard player")
	if not slot.is_active():
		return
	_check(slot.source is KeyboardInputSource,
		"the keyboard player gets a KeyboardInputSource (%s)" % slot.source.get_display_name())

	var fighter := slot.fighter as Fighter
	_check(fighter != null, "joining spawns a fighter")
	if fighter == null:
		return

	await _place(fighter, Vector3(-8, 0.5, CLEAR_LANE_Z))
	await _settle_on_floor(fighter)
	var start := fighter.global_position

	# D is right; the fighter should move under its own steam.
	await _hold_key(KEY_D, 40)
	var travelled := fighter.global_position.distance_to(start)
	_check(travelled > 2.0, "holding D actually moves the fighter (%.1f units)" % travelled)
	_check(fighter.get_state_id() == FighterState.RUN,
		"the keyboard player reaches the run state (%s)" % fighter.get_state_id())

	await _release_key(KEY_D)
	await _ticks(30)

	var before := fighter.attacks_started
	await _hold_key(KEY_J, 3)
	await _ticks(6)
	_check(fighter.attacks_started > before, "pressing J throws a punch")
	await _release_key(KEY_J)
	await _ticks(20)


func _settle_on_floor(fighter: Fighter) -> void:
	for i in 90:
		await get_tree().physics_frame
		if fighter.is_on_floor():
			return


func _hold_key(key: Key, ticks: int) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await _ticks(ticks)


func _release_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await get_tree().physics_frame


# --- Local helpers ---

func _place(fighter: Fighter, position: Vector3) -> void:
	# Guarded: the gamepad checks in this suite put a real GamepadInputSource in
	# a seat, and _source only answers for scripted ones. Unguarded this threw
	# on every placement after those ran -- harmless to the assertions, and
	# exactly the kind of standing error that hides the next real one.
	var source := _source(fighter)
	if source != null:
		source.release_all()
		source.move = Vector2.ZERO
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
