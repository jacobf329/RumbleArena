## Base for every fighter state.
##
## States own their own transitions and return the id of the state to enter
## next, or an empty StringName to stay put. This is the main defence against
## the if-statement soup that kills brawler codebases -- see GAME_DESIGN.md 9.
##
## `fighter` is typed as CharacterBody3D rather than Fighter to keep the state
## scripts free of a cyclic class_name dependency on fighter.gd.
class_name FighterState
extends RefCounted

const IDLE := &"idle"
const RUN := &"run"
const AIR := &"air"
const DASH := &"dash"
const ATTACK := &"attack"
const HITSTUN := &"hitstun"
const KNOCKDOWN := &"knockdown"
const BLOCK := &"block"

const STAY := &""

var fighter: CharacterBody3D


func setup(owning_fighter: CharacterBody3D) -> void:
	fighter = owning_fighter


func enter(_previous: StringName) -> void:
	pass


func exit() -> void:
	pass


## Return the next state id, or STAY.
func physics_update(_delta: float) -> StringName:
	return STAY


func get_id() -> StringName:
	return STAY
