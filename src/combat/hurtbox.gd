## The volume an attack's hitbox query looks for.
##
## Sits on the HURTBOX layer so a shape query can find fighters without also
## finding arena geometry, and so hitboxes never collide with fighter bodies.
class_name Hurtbox
extends Area3D

@export var fighter_path: NodePath = ^".."

var fighter: Node3D


func _ready() -> void:
	fighter = get_node_or_null(fighter_path)
	collision_layer = Layers.HURTBOX
	collision_mask = 0
	monitoring = false  # purely a target; it never needs to detect anything
