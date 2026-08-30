## Guarding. Cheap against chip, expensive against a real commitment.
class_name BlockState
extends FighterState


func get_id() -> StringName:
	return BLOCK


func enter(_previous: StringName) -> void:
	fighter.velocity.x = 0.0
	fighter.velocity.z = 0.0


func physics_update(delta: float) -> StringName:
	fighter.apply_gravity(delta)
	fighter.apply_ground_friction(delta)

	# Blockstun holds you in guard whether you like it or not; that is what makes
	# a blocked heavy still cost you your turn.
	if fighter.is_in_blockstun():
		return STAY

	if not fighter.is_on_floor():
		return AIR
	if fighter.stamina <= 0.0:
		# Guard break: the stamina bar is the real cost of turtling.
		fighter.grant_invulnerability(0)
		return IDLE
	if not fighter.get_input().is_held(InputFrame.Action.BLOCK):
		return RUN if fighter.get_move_direction() != Vector3.ZERO else IDLE
	if fighter.request_dash():
		return DASH
	return STAY
