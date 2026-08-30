## The shared smart camera: one view that has to keep up to four super-powered
## fighters readable at once.
##
## This is the riskiest system in the project. If it fails, pillar P3 fails with
## it, which is why it is built in M1 rather than last. Split-screen is the known
## escape hatch (docs/GAME_DESIGN.md section 10).
class_name ArenaCamera
extends Camera3D

## Fixed angles: the camera moves and zooms but never rotates, so "up on the
## stick" keeps meaning the same direction for the whole match.
@export var pitch_degrees := -50.0
@export var yaw_degrees := 0.0

@export_group("Framing")
@export var min_distance := 12.0
@export var max_distance := 34.0
## World units of breathing room kept around the outermost fighter.
@export var padding := 5.0
## Headroom above the tallest fighter, so nameplates are never clipped.
@export var head_room := 1.8
@export var look_height := 1.6

@export_group("Smoothing")
## Asymmetric by design: snapping in on a KO and back out again is nauseating,
## so the camera retreats quickly and returns slowly.
@export var zoom_out_speed := 7.0
@export var zoom_in_speed := 1.6
@export var pan_speed := 6.0

@export_group("Bounds")
## The camera focus is clamped inside this, so an arena edge never shows void.
@export var bounds := AABB(Vector3(-18, 0, -18), Vector3(36, 10, 36))

@export_group("Shake")
## Peak screen offset in world units at full strength.
@export var shake_scale := 0.06
## Seconds for a shake to decay to nothing.
@export var shake_decay := 3.5

var _targets: Array[Node3D] = []
var _focus := Vector3.ZERO
var _distance := 20.0
var _shake := 0.0


func _ready() -> void:
	rotation = Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), 0.0)
	reset_focus()


## Re-seeds framing. The harness calls this after handing the camera the arena's
## bounds, because a child's _ready runs before its parent's.
func reset_focus() -> void:
	_focus = bounds.get_center()
	_distance = max_distance
	_apply_transform()


func add_target(target: Node3D) -> void:
	if not _targets.has(target):
		_targets.append(target)


func remove_target(target: Node3D) -> void:
	_targets.erase(target)


func _physics_process(delta: float) -> void:
	_targets = _targets.filter(func(t: Node3D) -> bool: return is_instance_valid(t))
	var framed: Array[Node3D] = _targets.filter(func(t: Node3D) -> bool: return t.visible)
	if framed.is_empty():
		return

	var enclosing := _enclosing_box(framed)
	var desired_focus := _clamp_to_bounds(enclosing.get_center())
	var desired_distance := clampf(
		_required_distance(enclosing.get_center()), min_distance, max_distance)

	_focus = _focus.lerp(desired_focus, minf(pan_speed * delta, 1.0))

	var zoom_rate := zoom_out_speed if desired_distance > _distance else zoom_in_speed
	_distance = lerpf(_distance, desired_distance, minf(zoom_rate * delta, 1.0))

	_shake = maxf(_shake - shake_decay * delta, 0.0)
	_apply_transform()


func _enclosing_box(framed: Array[Node3D]) -> AABB:
	var box := AABB(framed[0].global_position, Vector3.ZERO)
	for target: Node3D in framed:
		box = box.expand(target.global_position)
	return box


## Distance at which every target fits the frustum.
##
## The targets are projected onto the camera's own right and up axes before
## being measured. Measuring a world-space span instead would fit a horizontal
## spread into the vertical field of view and zoom out far more than needed --
## and because the camera is pitched down, a world Y difference lands partly on
## screen-up and partly on screen-depth, which only the projection accounts for.
func _required_distance(center: Vector3) -> float:
	var right := global_transform.basis.x
	var up := global_transform.basis.y

	var half_width := 0.0
	var half_height := 0.0
	for target: Node3D in _targets.filter(func(t: Node3D) -> bool: return t.visible):
		var offset := target.global_position - center
		half_width = maxf(half_width, absf(offset.dot(right)))
		half_height = maxf(half_height, absf(offset.dot(up)))

	half_width += padding
	half_height += padding + head_room

	var vertical_half_fov := deg_to_rad(fov) * 0.5
	var horizontal_half_fov := atan(tan(vertical_half_fov) * _aspect())

	return maxf(
		half_width / maxf(tan(horizontal_half_fov), 0.01),
		half_height / maxf(tan(vertical_half_fov), 0.01)
	)


func _aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 1.0
	var rect := viewport.get_visible_rect().size
	return rect.x / rect.y if rect.y > 0.0 else 1.0


func _clamp_to_bounds(point: Vector3) -> Vector3:
	var low := bounds.position
	var high := bounds.end
	return Vector3(
		clampf(point.x, low.x, high.x),
		clampf(point.y, low.y, high.y),
		clampf(point.z, low.z, high.z)
	)


## Shared camera means shared shake -- every player feels the hit, not just the
## two involved. In a four-player game that reads as the arena reacting rather
## than as a private effect, which is why shake is global while hitstop is not.
func add_shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


func get_shake() -> float:
	return _shake


func _apply_transform() -> void:
	var look_at_point := _focus + Vector3.UP * look_height
	# The camera looks down its own -Z, so backing off means adding +Z.
	var basis := global_transform.basis
	global_position = look_at_point + basis.z * _distance

	if _shake > 0.0:
		# Offset along the camera's own right and up, so it reads as the screen
		# shaking rather than the camera wandering through the world.
		var amount := _shake * _shake * shake_scale * _distance
		global_position += basis.x * randf_range(-amount, amount) \
			+ basis.y * randf_range(-amount, amount)


## Current framing distance, for tests and for the M2 soft leash.
func get_distance() -> float:
	return _distance


func get_focus() -> Vector3:
	return _focus


## True when a target is close to leaving the frame at maximum zoom -- the cue
## for the soft leash and the off-screen indicator (M2).
func is_target_near_edge(target: Node3D, margin := 0.12) -> bool:
	if not is_instance_valid(target):
		return false
	if is_position_behind(target.global_position):
		return true
	var screen := unproject_position(target.global_position)
	var size := get_viewport().get_visible_rect().size
	var inset := size * margin
	return screen.x < inset.x or screen.y < inset.y \
		or screen.x > size.x - inset.x or screen.y > size.y - inset.y
