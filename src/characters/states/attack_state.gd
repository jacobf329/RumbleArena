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
var _hit_targets: Array = []


func get_id() -> StringName:
	return ATTACK


func enter(_previous: StringName) -> void:
	_attack = fighter.pending_attack
	var scale: float = fighter.character_def.get_attack_speed_scale()
	_startup = CombatMath.scale_ticks(_attack.ticks_startup, scale)
	_active = _attack.ticks_active
	_recovery = CombatMath.scale_ticks(_attack.ticks_recovery, scale)
	_tick = 0
	_connected = false
	_stepped = false
	_hit_targets.clear()
	fighter.attacks_started += 1


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	if _attack.halts_fall and _tick <= _startup + _active:
		fighter.velocity.y = maxf(fighter.velocity.y, -1.5)
	fighter.apply_attack_drift(delta)

	if _tick == _startup and not _stepped:
		_stepped = true
		fighter.apply_step(_attack.step_forward)

	if _tick >= _startup and _tick < _startup + _active:
		_query_hits()

	_tick += 1

	if _tick >= _startup + _active + _attack.cancel_window_start:
		var next: StringName = fighter.consume_cancel(_attack, _connected)
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
		if fighter.deal_hit(_attack, victim):
			_connected = true


func _finish() -> StringName:
	fighter.end_attack_chain()
	if not fighter.is_on_floor():
		return AIR
	return RUN if fighter.get_move_direction() != Vector3.ZERO else IDLE


## True once this attack has connected with anything -- the gate on confirms.
func has_connected() -> bool:
	return _connected
