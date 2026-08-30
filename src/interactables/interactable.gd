## Anything in the arena a fighter can act on, and the stat that gates it.
##
## This is the mechanism that ties character asymmetry to the environment
## (GAME_DESIGN.md section 3). Every interactable declares a stat and a tier; a
## fighter may use it only if their rating meets it.
##
## Crucially, a denied interactable still shows its prompt, greyed out, with the
## requirement visible. Players learn the stat system by being refused, and learn
## what the other ninjas can do by seeing what they themselves cannot. That is a
## teaching mechanism, not an oversight -- so `can_use` and `is_offered` are
## deliberately separate questions.
class_name Interactable
extends Area3D

@export var display_name: String = "Object"
## Verb shown in the prompt: "Lift", "Hack", "Climb".
@export var verb: String = "Use"
@export var required_stat: Stats.Type = Stats.Type.STRENGTH
@export_range(1, 5) var required_tier: int = 1


func _ready() -> void:
	collision_layer = Layers.INTERACTABLE
	collision_mask = 0
	monitoring = false  # a target, not a detector


## Does this fighter's stat block clear the requirement?
func can_use(fighter: Node3D) -> bool:
	var definition: CharacterDef = fighter.get("character_def")
	if definition == null:
		return false
	return definition.meets(required_stat, required_tier)


## Whether the object is in a state to be offered at all -- already carried,
## already broken, already hacked. Independent of whether the fighter qualifies.
func is_offered(_fighter: Node3D) -> bool:
	return true


## Override with the actual effect. Returns whether anything happened.
func use(_fighter: Node3D) -> bool:
	return false


func requirement_text() -> String:
	return "%s %d" % [Stats.display_name(required_stat), required_tier]


## What the prompt says. A refusal names the requirement, so being denied
## teaches the player something instead of just failing.
func prompt_text(fighter: Node3D) -> String:
	if can_use(fighter):
		return "%s %s" % [verb, display_name]
	return "%s  -  needs %s" % [display_name, requirement_text()]
