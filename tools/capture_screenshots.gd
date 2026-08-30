## Dev tool: poses four fighters in the arena and writes PNGs.
##
## Run under a virtual framebuffer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 \
##       --rendering-method gl_compatibility res://tools/capture_screenshots.tscn -- <out_dir>
extends Node

const MAIN_SCENE := preload("res://scenes/main.tscn")

## Poses chosen to show the whole arena vocabulary at once: floor, centre
## platform, low ledge and the high ledge only a double-jumper can reach.
const POSES := [
	Vector3(-3.0, 0.3, 7.0),
	Vector3(0.0, 3.9, 0.0),
	Vector3(12.0, 2.4, 6.0),
	Vector3(-12.5, 4.5, -7.0),
]

var _main: Node3D
var _fighters: Array[Fighter] = []
var _out_dir := "/tmp"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_out_dir = args[0]

	_main = MAIN_SCENE.instantiate()
	add_child(_main)
	await get_tree().physics_frame
	PlayerManager.join_enabled = false

	for i in 4:
		var slot: PlayerSlot = PlayerManager.slots[i]
		slot.source = ScriptedInputSource.new()
		PlayerManager.player_joined.emit(slot)
		await get_tree().physics_frame
		_fighters.append(slot.fighter as Fighter)

	await _pose(POSES)
	await _capture("m1_four_players.png")

	await _roster_shot()
	await _combat_shot()
	await _permission_shot()
	await _climb_shot()

	# Two fighters close together, to show the camera pushing in.
	await _pose([Vector3(-2.5, 0.3, 11.0), Vector3(2.5, 0.3, 11.0),
		Vector3(-1.0, 0.3, 13.5), Vector3(4.0, 0.3, 13.5)])
	await _capture("m1_camera_close.png")

	get_tree().quit()


## Four fighters side by side, so the per-player hue shift can be judged: one
## mesh and one texture, recoloured only where the crimson is.
func _roster_shot() -> void:
	await _pose([
		Vector3(-6.0, 0.3, 13.0), Vector3(-2.0, 0.3, 13.0),
		Vector3(2.0, 0.3, 13.0), Vector3(6.0, 0.3, 13.0),
	])
	for fighter in _fighters:
		fighter.snap_facing(Vector3.BACK)
	await get_tree().physics_frame
	await _capture("roster.png")


## Catches the frame a heavy connects: hit spark, flash, and the meters
## reacting. This is the shot that actually shows whether the impact reads.
func _combat_shot() -> void:
	var attacker := _fighters[0]
	var victim := _fighters[3]

	# Open floor south of the ramp, so nothing stands between the camera and the
	# point of contact.
	await _pose([
		Vector3(-4.0, 0.3, 13.5), Vector3(2.8, 0.3, 12.2),
		Vector3(-8.0, 0.3, 12.6), Vector3(-2.6, 0.3, 13.5),
	])
	attacker.snap_facing(Vector3.RIGHT)
	victim.snap_facing(Vector3.LEFT)
	victim.health = victim.max_health * 0.55
	attacker.power = attacker.max_power * 0.7

	var connected := [false]
	victim.damaged.connect(func(_result: HitResult) -> void: connected[0] = true)

	var source := attacker.slot.source as ScriptedInputSource
	source.hold(InputFrame.Action.HEAVY, true)
	await get_tree().physics_frame
	source.hold(InputFrame.Action.HEAVY, false)

	for tick in 120:
		await get_tree().physics_frame
		if connected[0]:
			break
	await _capture("m2_impact.png")


## The teaching mechanism, side by side: the same pillar offered to the fighter
## who qualifies and refused, with its requirement, to the one who does not.
func _permission_shot() -> void:
	var arena := _main.get_node("Arena")
	var west: Node3D = arena.get_node("Interactables/PillarWest")
	var east: Node3D = arena.get_node("Interactables/PillarEast")

	await _pose([
		west.global_position + Vector3(0, 0.3, 1.15),
		east.global_position + Vector3(0, 0.3, 1.15),
		Vector3(-9.0, 0.3, 12.0), Vector3(9.0, 0.3, 12.0),
	])
	# Kurogane (STR 5) faces the west pillar, Null (STR 1) faces the east one.
	_fighters[0].snap_facing(Vector3.FORWARD)
	_fighters[1].snap_facing(Vector3.FORWARD)
	for tick in 20:
		await get_tree().physics_frame
	await _capture("m3_permission.png")


## Yamabuki partway up the comms tower: the AGILITY gate's own verb, and the
## only route to the one thing in the arena nobody else can reach.
func _climb_shot() -> void:
	var wall: Climbable = _main.get_node("Arena/Interactables/TowerFace")
	var yamabuki := _fighters[3]
	var normal := wall.outward_normal()

	await _pose([
		Vector3(-7.0, 0.3, -11.0), Vector3(-9.5, 0.3, -8.0), Vector3(-6.0, 0.3, -14.0),
		Vector3(wall.global_position.x, 0.3, wall.global_position.z) + normal * 0.9,
	])
	yamabuki.snap_facing(-normal)
	await get_tree().physics_frame

	var source := yamabuki.slot.source as ScriptedInputSource
	source.hold(InputFrame.Action.INTERACT, true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	source.hold(InputFrame.Action.INTERACT, false)

	source.move = Vector2(0, 1)
	for tick in 55:
		await get_tree().physics_frame
	source.move = Vector2.ZERO
	await _capture("m3_climb.png")


func _pose(positions: Array) -> void:
	for i in _fighters.size():
		_fighters[i].global_position = positions[i]
		_fighters[i].velocity = Vector3.ZERO
	# Let gravity settle everyone onto the surface under them, and give the
	# camera time to finish its slow zoom-in before the shutter.
	for tick in 300:
		await get_tree().physics_frame
	for fighter in _fighters:
		var focus := Vector3(0.0, fighter.global_position.y, 0.0)
		if fighter.global_position.distance_to(focus) > 0.5:
			fighter.look_at(focus, Vector3.UP)


func _capture(filename: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _out_dir.path_join(filename)
	var error := image.save_png(path)
	print("wrote %s (%d)" % [path, error])
