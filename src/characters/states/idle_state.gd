## Standing still on the ground.
class_name IdleState
extends FighterState


func get_id() -> StringName:
	return IDLE


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	fighter.apply_ground_friction(delta)

	if fighter.request_dash():
		return DASH
	if fighter.request_attack():
		return ATTACK
	if fighter.request_block():
		return BLOCK
	if fighter.request_jump():
		return AIR
	if not fighter.is_on_floor():
		return AIR
	if fighter.get_move_direction() != Vector3.ZERO:
		return RUN
	return STAY
