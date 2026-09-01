## The actual ninja, in the actual colour, on the select screen.
##
## A character select that shows only names and numbers is a spreadsheet. This
## renders the real model through the real hue shader, so the thing you pick is
## the thing you get -- and it costs nothing to keep in step, because it is the
## same FighterVisual the arena uses rather than a portrait somebody has to
## remember to redraw.
class_name CharacterPreview
extends SubViewportContainer

@onready var _visual: FighterVisual = $SubViewport/Visual

var _turn := 0.0


func _ready() -> void:
	stretch = true


func set_character(_definition: CharacterDef, colour: Color) -> void:
	if not is_node_ready():
		await ready
	_visual.set_player_colour(colour)


## Slowly turning, and walking on the spot: with no idle clip the locomotion
## animation at a low speed is the closest thing to standing there, and a
## motionless model reads as a broken one.
func _process(delta: float) -> void:
	if _visual == null:
		return
	_turn = wrapf(_turn + delta * 0.35, 0.0, TAU)
	# Half a turn plus the sway: the model is authored facing +Z and the fighter
	# scene flips it to match Godot's -Z forward, which points it directly away
	# from a camera sitting in front of it. Correct in the arena, backwards here.
	_visual.rotation.y = PI + sin(_turn) * 0.45
	_visual.play_locomotion(0.0, false)


func set_dimmed(dim: bool) -> void:
	modulate = Color(0.45, 0.45, 0.5) if dim else Color.WHITE
