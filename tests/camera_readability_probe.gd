## Not a test -- a measuring instrument for how big a fighter actually reads.
##
## The shared camera is the riskiest system in the project, and "is it zoomed
## out too far" is not a question anybody can answer by looking at one
## screenshot. This projects a fighter's feet and head to screen space at a
## range of spreads and reports the height in pixels, which is the number the
## decision actually turns on.
extends TestHarness

const SPREADS := [0.0, 2.0, 4.0, 6.0, 9.0, 12.0, 16.0, 20.0, 26.0]

var _camera_node: ArenaCamera


func _init() -> void:
	test_name = "camera readability probe"


func _run() -> void:
	var fighters: Array[Fighter] = []
	for i in 4:
		fighters.append(await _join(i))
	await _ticks(20)
	_camera_node = _camera

	print("")
	print("fov %.0f, pitch %.0f deg" % [_camera_node.fov, _camera_node.pitch_degrees])
	print("  spread    camera    fighter %% of screen   worst edge (1.0 = clipped)")

	for spread: float in SPREADS:
		_arrange(fighters, spread)
		# Long enough for the smoothing to settle: the camera zooms out fast and
		# back in slowly, so a short wait would measure the transition.
		await _ticks(240)
		print("  %5.1f m   %5.1f m   %10.1f %%   %14.2f" % [
			spread, _camera_node.get_distance(), 100.0 * _screen_fraction(),
			_worst_edge(fighters)])

	_check(true, "measured")


## What fraction of the screen's height a standing fighter covers.
##
## Computed from the camera's own distance and field of view rather than by
## projecting to pixels: unproject answers in the real viewport's units, and the
## headless viewport is not the shape anybody plays on -- dividing those pixels
## by an assumed 1080 would have reported half the truth and sent the tuning the
## wrong way.
##
## The cosine is the pitch foreshortening: the camera looks down at 50 degrees,
## so a 1.8m vertical fighter only covers 1.8*cos(50) of the screen's up axis.
func _screen_fraction() -> float:
	const FIGHTER_HEIGHT := 1.8
	var apparent: float = FIGHTER_HEIGHT * cos(deg_to_rad(absf(_camera_node.pitch_degrees)))
	var visible_height: float = 2.0 * _camera_node.get_distance() \
		* tan(deg_to_rad(_camera_node.fov) * 0.5)
	return apparent / maxf(visible_height, 0.001)


## How close the outermost fighter is to the edge of the frame, as a fraction of
## the half-frame: 0 is dead centre, 1 is exactly on the edge, above 1 is off
## screen. This is the number that says whether a padding reduction has gone too
## far, and it is the only reason it is safe to reduce padding at all.
func _worst_edge(fighters: Array[Fighter]) -> float:
	var right: Vector3 = _camera_node.global_transform.basis.x
	var up: Vector3 = _camera_node.global_transform.basis.y
	var distance: float = _camera_node.get_distance()
	var half_height: float = distance * tan(deg_to_rad(_camera_node.fov) * 0.5)
	# 16:9, the shape the game is actually played on.
	var half_width: float = half_height * (16.0 / 9.0)

	var worst := 0.0
	for fighter in fighters:
		# The top of the nameplate, not the feet: that is what clips first.
		var offset: Vector3 = (fighter.global_position + Vector3.UP * 2.7) \
			- _camera_node.get_focus()
		worst = maxf(worst, absf(offset.dot(right)) / maxf(half_width, 0.001))
		worst = maxf(worst, absf(offset.dot(up)) / maxf(half_height, 0.001))
	return worst


## Four fighters on a circle of the given radius, centred on open floor.
func _arrange(fighters: Array[Fighter], spread: float) -> void:
	var centre := Vector3(0.0, 0.3, 11.0)
	for i in fighters.size():
		var angle := TAU * float(i) / float(fighters.size())
		fighters[i].global_position = centre \
			+ Vector3(cos(angle), 0.0, sin(angle)) * spread * 0.5
		fighters[i].velocity = Vector3.ZERO
		_source(fighters[i]).move = Vector2.ZERO
