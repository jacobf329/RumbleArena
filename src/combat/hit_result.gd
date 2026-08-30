## One resolved hit, handed from the attacker's attack state to the victim.
class_name HitResult
extends RefCounted

var attacker: Node3D
var attack: AttackDef
var damage: float
var knockback: Vector3
var hitstun_ticks: int
var hitstop_ticks: int
var blocked: bool = false
## True when the attacker launched this strike inside the rhythm window.
var on_beat: bool = false
var position: Vector3
