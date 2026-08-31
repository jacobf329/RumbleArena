## Runs one attack's frame data: startup, active, recovery.
##
## The hitbox is a shape query rather than an Area3D, so it is live on exactly
## the ticks the frame data says and not one tick later -- Area3D overlaps only
## settle on the next physics step, which would smear every active window.
class_name AttackState
extends FighterState

var _attack: AttackDef
var _tick := 0
var _startup := 0
var _active := 0
var _recovery := 0
var _connected := false
var _stepped := false
var _on_beat := false
var _hit_targets: Array = []
## The fighter currently held by a grab, if this move is one.
var _grabbed: Node = null
var _fired := false
## A slam that has been launched and has not hit the ground yet.
var _slam_pending := false


func get_id() -> StringName:
	return ATTACK


func enter(_previous: StringName) -> void:
	_attack = fighter.pending_attack
	_on_beat = fighter.consume_pending_on_beat()

	var scale: float = fighter.get_attack_speed_scale()
	if _on_beat:
		# Rhythm pays in speed as well as damage, so a clean chain visibly
		# outruns a mashed one rather than just reading higher on the numbers.
		scale *= CombatMath.ON_BEAT_STARTUP_SCALE

	_startup = CombatMath.scale_ticks(_attack.ticks_startup, scale)
	_active = _attack.ticks_active
	_recovery = CombatMath.scale_ticks(_attack.ticks_recovery, scale)
	_tick = 0
	_connected = false
	_stepped = false
	_hit_targets.clear()
	_grabbed = null
	_fired = false
	_slam_pending = _attack.slams_on_landing and not fighter.is_on_floor()
	fighter.attacks_started += 1
	fighter.begin_attack(_attack, _on_beat, _startup, _active + _recovery)


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	if _attack.halts_fall and _tick <= _startup + _active:
		fighter.velocity.y = maxf(fighter.velocity.y, -1.5)
	fighter.apply_attack_drift(delta)

	if _tick == _startup and not _stepped:
		_stepped = true
		fighter.apply_step(_attack.step_forward)
		if _attack.dive_speed > 0.0 and not fighter.is_on_floor():
			# Straight down, horizontal momentum discarded. A slam you could
			# steer mid-descent would be a better approach tool than the jump
			# kick, which is the move that is supposed to cover ground.
			fighter.velocity = Vector3(0.0, -_attack.dive_speed, 0.0)

	# Cast before resolving hits, not after. The other way round, the finisher's
	# own connect credited power on the same tick the cost was checked, so the
	# move paid for its own fireball and the meter meant nothing.
	if _tick == _startup and not _fired:
		_fired = true
		# Powers resolve before hits so a move that repositions the fighter --
		# Blink Strike -- still lands its own strike from where it arrived.
		fighter.activate_power(_attack)
		fighter.try_launch_fireball(_attack)

	if _tick >= _startup and _tick < _startup + _active:
		_query_hits()

	if _grabbed != null:
		_carry_grabbed()

	if _slam_pending and _tick >= _startup:
		if fighter.is_on_floor():
			_slam_pending = false
			fighter.slam_impact(_attack)
		else:
			# Pinned to the first active frame, so the hitbox stays live the
			# whole way down instead of the move timing out in the air.
			_tick = _startup

	_tick += 1

	var window_opens := _startup + _active + _attack.cancel_window_start
	if _tick >= window_opens:
		var next: StringName = fighter.consume_cancel(
			_attack, _connected, _tick - window_opens)
		if next != STAY:
			return next

	if _tick >= _startup + _active + _recovery:
		return _finish()
	return STAY


func _query_hits() -> void:
	var victims: Array = fighter.query_hitbox(_attack)
	for victim in victims:
		if _hit_targets.has(victim):
			continue
		_hit_targets.append(victim)

		if _attack.is_grab and victim is Fighter:
			if fighter.seize(victim):
				_grabbed = victim
				_connected = true
			continue

		if fighter.deal_hit(_attack, victim):
			_connected = true


## Holds the victim in front of the attacker until the throw, then launches
## them. A grab that is interrupted simply drops whoever was held.
func _carry_grabbed() -> void:
	if not is_instance_valid(_grabbed):
		_grabbed = null
		return
	if _tick >= _attack.grab_release_tick:
		fighter.throw_grabbed(_grabbed, _attack)
		_grabbed = null
		return
	fighter.hold_grabbed(_grabbed)


func exit() -> void:
	if _grabbed != null and is_instance_valid(_grabbed):
		fighter.release_grabbed(_grabbed)
	_grabbed = null
	fighter.end_attack_visual()


func _finish() -> StringName:
	fighter.end_attack_chain()
	if not fighter.is_on_floor():
		return AIR
	return RUN if fighter.get_move_direction() != Vector3.ZERO else IDLE


## True once this attack has connected with anything -- the gate on confirms.
func has_connected() -> bool:
	return _connected
