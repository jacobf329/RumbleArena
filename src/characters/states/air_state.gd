## Airborne, whether rising from a jump or walking off a ledge.
##
## Coyote time and jump buffering live on the fighter so that both the ground
## states and this one consume the same timers.
class_name AirState
extends FighterState


func get_id() -> StringName:
	return AIR


func physics_update(delta: float) -> StringName:
	var direction: Vector3 = fighter.get_move_direction()

	fighter.apply_gravity(delta)
	fighter.apply_variable_jump_cut()
	fighter.apply_air_acceleration(direction, delta)
	fighter.face_movement(direction, delta)

	# A jump landing here is the double jump; the ground jump was consumed by
	# whichever ground state we left, or by coyote time just after leaving it.
	fighter.request_jump()

	if fighter.request_dash():
		return DASH
	if fighter.is_on_floor():
		fighter.on_landed()
		return RUN if direction != Vector3.ZERO else IDLE
	return STAY
