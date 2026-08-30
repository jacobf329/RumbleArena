## Moving under the player's own steam, feet on the floor.
class_name RunState
extends FighterState


func get_id() -> StringName:
	return RUN


func physics_update(delta: float) -> StringName:
	var direction: Vector3 = fighter.get_move_direction()

	fighter.apply_gravity(delta)
	fighter.apply_ground_acceleration(direction, delta)
	fighter.face_movement(direction, delta)

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
	if direction == Vector3.ZERO:
		return IDLE
	return STAY
