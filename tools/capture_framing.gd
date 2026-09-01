## Dev tool: what the shared camera actually shows, at a tight fight and a
## spread one. The camera is the riskiest system in the project and its tuning
## is not a thing to judge from numbers alone.
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

var _out := "/tmp"
var _fighters: Array[Fighter] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]

	var main: Node3D = MAIN_SCENE.instantiate()
	add_child(main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false
	(main.get_node("Match") as MatchManager).auto_start = false
	(main.get_node("CharacterSelect") as CharacterSelect).enabled = false

	for i in 4:
		var slot: PlayerSlot = PlayerManager.slots[i]
		slot.source = ScriptedInputSource.new()
		PlayerManager.player_joined.emit(slot)
		await get_tree().physics_frame
		_fighters.append(slot.fighter as Fighter)

	await _at_spread(2.5, "framing-tight")
	await _at_spread(9.0, "framing-spread")
	get_tree().quit()


func _at_spread(spread: float, name: String) -> void:
	var centre := Vector3(0.0, 0.3, 11.0)
	for i in _fighters.size():
		var angle := TAU * float(i) / 4.0
		_fighters[i].global_position = centre \
			+ Vector3(cos(angle), 0.0, sin(angle)) * spread * 0.5
		_fighters[i].velocity = Vector3.ZERO
	for i in 260:
		await get_tree().physics_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, name])
	print("wrote %s at %.1f m spread" % [name, spread])
