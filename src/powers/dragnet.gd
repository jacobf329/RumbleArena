## Yamabuki's ultimate: the same line, thrown at people instead of scenery.
##
## Everyone in range is hauled in and dumped at her feet. It does almost no
## damage, which is the point -- an AGILITY character's ultimate should create
## the situation rather than finish it, and four fighters suddenly stacked in
## one place is the most dangerous thing that can happen in this game.
class_name Dragnet
extends Power

@export var radius: float = 9.0
## Where they end up, measured out from her. Not zero: landing everyone inside
## her own capsule makes the physics solver shove them somewhere arbitrary.
@export var gather_distance: float = 1.5
## How long the haul takes. Solved as an arc rather than a shove, so somebody
## across the arena and somebody standing next to her arrive together -- and so
## the trip happens in the air, where the ground cannot eat it.
@export var haul_seconds: float = 0.45
@export var haul_damage: float = 4.0
@export var haul_hitstun: int = 34


func activate(fighter: Node3D) -> void:
	for node in fighter.get_tree().get_nodes_in_group(&"fighters"):
		var victim := node as Fighter
		if victim == null or victim == fighter or victim.is_eliminated:
			continue
		if victim.is_invulnerable():
			continue

		var offset: Vector3 = fighter.global_position - victim.global_position
		var flat := Vector3(offset.x, 0.0, offset.z)
		var distance := flat.length()
		if distance > radius or distance < 0.05:
			continue

		# Hauled to a ring around her rather than into her, on an arc that lands
		# in haul_seconds whatever the distance.
		var pull := flat.normalized()
		var travel := maxf(distance - gather_distance, 0.0)
		var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 24.0)
		var launch := pull * (travel / haul_seconds)
		launch.y = (offset.y / haul_seconds) + 0.5 * gravity * haul_seconds

		var result := HitResult.new()
		result.attacker = fighter
		result.damage = haul_damage
		result.knockback = launch
		result.hitstun_ticks = haul_hitstun
		result.hitstop_ticks = 5
		result.position = victim.global_position + Vector3.UP
		victim.take_hit(result)
		# take_hit sets the velocity; this stops hitstun drag from deleting it
		# before they have crossed the floor.
		victim.apply_launch(launch, ceili(haul_seconds * 60.0))
