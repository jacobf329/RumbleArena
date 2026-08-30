## The chain finisher's projectile.
##
## Cast by completing punch, punch, kick: landing the full light chain ends in a
## fireball rather than just a kick. It costs power, so the meter finally buys
## something, and running dry simply gives you the kick on its own.
class_name Fireball
extends Projectile

const BALL_RADIUS := 0.42
const BALL_LIFETIME := 1.9
const COLOUR := Color(1.0, 0.62, 0.22)


static func cast(parent: Node, at: Vector3, direction: Vector3, speed: float,
		hit_damage: float, knockback: float, by: Node3D) -> Fireball:
	var ball := Fireball.new()
	ball.velocity = direction.normalized() * speed
	ball.damage = hit_damage
	ball.shooter = by
	ball.radius = BALL_RADIUS
	ball.lifetime = BALL_LIFETIME
	ball.knockback_speed = knockback
	ball.hitstun = 30
	ball.hitstop = 7
	parent.add_child(ball)
	ball.global_position = at
	ball._tint(COLOUR)
	return ball


## Fireballs fly flat rather than arcing: a projectile that drops is a trap for
## the caster at any range worth using it from.
func _physics_process(delta: float) -> void:
	velocity.y = 0.0
	super(delta)
