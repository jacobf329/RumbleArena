## The body a character wears: a model, its animation clips, and how to recolour
## it.
##
## Pulled out of FighterVisual as soon as there was a second model to wear. The
## rule in docs/GAME_DESIGN.md section 9 is that adding a ninja is authoring a
## .tres and never editing fighter.gd -- that was true of the stat block and the
## powers from the start, and was quietly untrue of the art: a second model would
## have meant a second code path. Now it is a resource, and every consumer of a
## body -- the fighter, the select preview, Jinsoku's decoy -- gets it from the
## character rather than from a constant.
##
## The contract a model has to meet is the clip names, not the skeleton: the
## moveset names "roundhouse_kick" and expects a clip called that in whatever
## library the character brought. Two packs with the same clip names are
## interchangeable; a pack that calls its kick something else gets renamed at
## build time rather than remapped at runtime, because a moveset is shared
## between characters and must not learn one of their vocabularies.
class_name CharacterVisual
extends Resource

@export var display_name: String = ""

@export_group("Model")
@export var model: PackedScene
## Clip library, keyed by the names the movesets use. Built from the raw
## exports by tools/build_animation_library.gd.
@export var animations: AnimationLibrary
## Multiplier that puts the model's height on the 1.8m collision capsule.
@export var model_scale: float = 1.065
## Models authored facing +Z get turned to meet Godot's -Z forward. A pack that
## already faces -Z sets this false rather than being rotated in every scene
## that instances it.
@export var faces_positive_z: bool = true

@export_group("Recolour")
## The MeshInstance3D inside the model that wears the recolour shader. Empty
## means "the first one found", which is right for a single-mesh export.
@export var mesh_node: String = ""
## Hue of the colour in the source texture that gets rotated onto the player's
## slot colour. Measured from the atlas, not guessed.
@export_range(0.0, 1.0) var source_hue: float = 0.0
