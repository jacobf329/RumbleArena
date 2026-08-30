## Scenery an attack can destroy, if the attacker is strong enough.
##
## Deliberately not an Interactable: you break it by hitting it, not by pressing
## a button, so there is no prompt. The refusal still has to read, though -- a
## fighter who is too weak gets a spark and no damage rather than silence.
class_name Breakable
extends Area3D

signal broken(at: Vector3)

@export var display_name: String = "Server Rack"
## STRENGTH needed to damage this at all.
@export_range(1, 5) var break_tier: int = 2
@export var max_health: float = 30.0
## Debris left behind, which anyone can then pick up and throw.
@export var debris_count: int = 2
@export var debris_scene: PackedScene

var health: float


func _ready() -> void:
	collision_layer = Layers.BREAKABLE
	collision_mask = 0
	monitoring = false
	health = max_health


func can_be_broken_by(fighter: Node3D) -> bool:
	var definition: CharacterDef = fighter.get("character_def")
	return definition != null and definition.meets(Stats.Type.STRENGTH, break_tier)


## Returns true if the hit actually did damage, so the attacker can tell the
## difference between breaking something and bouncing off it.
func take_attack(amount: float, attacker: Node3D) -> bool:
	if not can_be_broken_by(attacker):
		return false
	health -= amount
	if health <= 0.0:
		_shatter()
	return true


func _shatter() -> void:
	broken.emit(global_position)
	if debris_scene != null:
		var parent := get_parent()
		for i in debris_count:
			var piece: Node3D = debris_scene.instantiate()
			parent.add_child(piece)
			# Fan the pieces out so they do not stack inside one another.
			var angle := TAU * float(i) / float(maxi(debris_count, 1))
			piece.global_position = global_position \
				+ Vector3(cos(angle), 0.0, sin(angle)) * 1.1 + Vector3.UP * 0.4
	queue_free()
