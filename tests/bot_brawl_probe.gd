## Not a test -- a measuring instrument. Four bots, no humans, one minute.
##
## It asserts nothing, because what it is for is the questions no assertion
## answers: does a four-way brawl actually go anywhere, and can one shared
## camera frame it? The numbers it prints are what the bots' targeting and
## stall-recovery were tuned against.
##
##   godot --headless --path . res://tests/bot_brawl_probe.tscn -- --pull=0.9
##
## Read it as: p50 spread is how far apart the fight usually is, "spread > 20 m"
## is the fraction of the match the camera is fighting the fighters, and wedged
## ticks are bots pushing into scenery they cannot walk through.
extends TestHarness

var _spreads: Array[float] = []
var _wedged := {}
var _wedge_spot := {}
var _carrying := {}
var _pickups := 0
var _throws := 0
var _offscreen := 0
var _edge_worst := 0.0


func _init() -> void:
	test_name = "bot brawl probe"


func _run() -> void:
	var pull := BotInputSource.DEFAULT_CROWD_PULL
	var seconds := 60
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pull="):
			pull = float(arg.split("=")[1])
		elif arg.begins_with("--seconds="):
			seconds = int(arg.split("=")[1])

	match_manager.auto_start = true
	match_manager.countdown_seconds = 0.2
	match_manager.stocks_per_player = 3
	match_manager.match_seconds = float(seconds) + 30.0
	for i in 4:
		var slot := PlayerManager.add_bot()
		(slot.source as BotInputSource).crowd_pull = pull
	await _ticks(30)

	var samples := 0
	var attacking := 0
	var spread_sum := 0.0
	var distance_sum := 0.0

	for i in 60 * seconds:
		await get_tree().physics_frame
		if match_manager.phase != MatchManager.Phase.FIGHTING:
			break

		# A bot whose feet are moving but whose body is not is stuck on scenery.
		for slot: PlayerSlot in PlayerManager.get_active_slots():
			var stuck := slot.fighter as Fighter
			if stuck == null or stuck.is_eliminated:
				continue
			if stuck.get_state_id() == FighterState.RUN \
					and slot.get_frame().move.length() > 0.5 \
					and Vector2(stuck.velocity.x, stuck.velocity.z).length() < 0.6:
				_wedged[slot.get_label()] = _wedged.get(slot.get_label(), 0) + 1
				_wedge_spot[slot.get_label()] = stuck.global_position

		# Props actually used, not just props reachable. Tuning the fetch rule
		# until the brawl metrics looked healthy could equally have meant tuning
		# it until bots never touched anything.
		for slot: PlayerSlot in PlayerManager.get_active_slots():
			var hands := slot.fighter as Fighter
			if hands == null:
				continue
			var held: bool = hands.carried != null
			var was: bool = _carrying.get(slot.get_label(), false)
			if held and not was:
				_pickups += 1
			elif was and not held:
				_throws += 1
			_carrying[slot.get_label()] = held

		if i % 6 != 0:
			continue
		samples += 1
		var live: Array[Vector3] = []
		for slot: PlayerSlot in PlayerManager.get_active_slots():
			var f := slot.fighter as Fighter
			if f == null or f.is_eliminated:
				continue
			live.append(f.global_position)
			if f.get_state_id() == FighterState.ATTACK:
				attacking += 1
		var widest := 0.0
		for a in live:
			for b in live:
				widest = maxf(widest, a.distance_to(b))
		# Whether anybody actually left the frame. Tightening the camera's padding
		# is only safe if knockback cannot outrun the zoom-out, and that is a
		# question about live play rather than about staged spacing.
		var edge := _worst_edge()
		_edge_worst = maxf(_edge_worst, edge)
		if edge > 1.0:
			_offscreen += 1

		_spreads.append(widest)
		spread_sum += widest
		distance_sum += _camera.get_distance()

	_spreads.sort()
	print("")
	print("crowd_pull %.2f over %d samples" % [pull, samples])
	print("  spread     p50 %.1f m   p90 %.1f m   p99 %.1f m   worst %.1f m"
		% [_pct(50), _pct(90), _pct(99), _spreads[-1] if _spreads.size() else 0.0])
	print("  camera is chasing a spread over 20 m for %.1f%% of the match"
		% (100.0 * _above(20.0)))
	print("  mean camera distance %.1f m" % (distance_sum / maxf(samples, 1)))
	print("  fighters mid-attack per sample %.2f" % (float(attacking) / maxf(samples, 1)))
	print("  props picked up %d, thrown %d" % [_pickups, _throws])
	print("  worst edge %.2f (1.0 = on the frame edge), samples off screen %d of %d"
		% [_edge_worst, _offscreen, samples])
	print("  wedged ticks %s" % _wedged)
	print("  last wedge spots %s" % _wedge_spot)
	print("  phase after: %s" % match_manager.phase_name())
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		var f := slot.fighter as Fighter
		print("  %s skill %.2f  stocks %d  hp %.0f" % [
			slot.get_label(), (slot.source as BotInputSource).skill,
			match_manager.get_stocks(slot.index), f.health])
	_check(true, "the brawl ran")


## How close the outermost fighter got to leaving the frame.
func _worst_edge() -> float:
	var right: Vector3 = _camera.global_transform.basis.x
	var up: Vector3 = _camera.global_transform.basis.y
	var half_height: float = _camera.get_distance() * tan(deg_to_rad(_camera.fov) * 0.5)
	var half_width: float = half_height * (16.0 / 9.0)

	var worst := 0.0
	for slot: PlayerSlot in PlayerManager.get_active_slots():
		var fighter := slot.fighter as Fighter
		if fighter == null or fighter.is_eliminated:
			continue
		var offset: Vector3 = (fighter.global_position + Vector3.UP * 2.7) - _camera.get_focus()
		worst = maxf(worst, absf(offset.dot(right)) / maxf(half_width, 0.001))
		worst = maxf(worst, absf(offset.dot(up)) / maxf(half_height, 0.001))
	return worst


func _pct(p: float) -> float:
	if _spreads.is_empty():
		return 0.0
	return _spreads[clampi(int(_spreads.size() * p / 100.0), 0, _spreads.size() - 1)]


func _above(limit: float) -> float:
	var over := 0
	for value in _spreads:
		if value > limit:
			over += 1
	return float(over) / maxf(_spreads.size(), 1)
