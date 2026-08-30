## An arena: the geometry, its spawn points, and the volume the camera may look at.
##
## Arenas are compact vertical rooms rather than open fields. That is a direct
## consequence of the shared-camera decision -- four fighters have to stay
## framable (docs/GAME_DESIGN.md section 2).
class_name Arena
extends Node3D

@export var display_name := "Untitled Arena"
## Focus volume for the shared camera. Kept a little inside the walls.
@export var camera_bounds := AABB(Vector3(-14, 0, -14), Vector3(28, 9, 28))


func get_spawn_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var container := get_node_or_null("SpawnPoints")
	if container != null:
		for child in container.get_children():
			if child is Node3D:
				points.append((child as Node3D).global_position)
	if points.is_empty():
		points.append(Vector3.ZERO)
	return points


## Spawn points cycle if there are more players than markers, so the arena is
## never the reason a fourth player cannot join.
func get_spawn_point(index: int) -> Vector3:
	var points := get_spawn_points()
	return points[index % points.size()]
