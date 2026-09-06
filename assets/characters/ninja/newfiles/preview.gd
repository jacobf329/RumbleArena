extends Node3D
var actor: Node3D
var camera: Camera3D
var selector: OptionButton
var status: Label
var orbit := 0.35
var distance := 4.1

func _ready() -> void:
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("171c25")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("d4def0")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	light.light_energy = 2.0
	add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 145, 0)
	fill.light_energy = 0.8
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("2b3340")
	floor_mesh.material_override = floor_material
	add_child(floor_mesh)
	actor = preload("res://ninja_actor.tscn").instantiate()
	add_child(actor)
	camera = Camera3D.new()
	camera.fov = 44
	add_child(camera)
	_update_camera()
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := VBoxContainer.new()
	panel.position = Vector2(24, 20)
	panel.add_theme_constant_override("separation", 12)
	canvas.add_child(panel)
	var title := Label.new()
	title.text = "ARMORED NINJA / CUSTOM MOTION"
	title.add_theme_font_size_override("font_size", 24)
	panel.add_child(title)
	selector = OptionButton.new()
	for move in actor.get_moves():
		selector.add_item(move)
	selector.item_selected.connect(_select)
	panel.add_child(selector)
	var replay := Button.new()
	replay.text = "Replay selected move"
	replay.pressed.connect(func(): _select(selector.selected))
	panel.add_child(replay)
	var speed := HSlider.new()
	speed.min_value = 0.1
	speed.max_value = 1.5
	speed.step = 0.1
	speed.value = 1.0
	speed.value_changed.connect(func(value): actor.animation_player.speed_scale = value)
	panel.add_child(speed)
	status = Label.new()
	status.text = "Playback speed  |  Drag right mouse to orbit  |  Wheel to zoom"
	panel.add_child(status)
	_select(0)
	if "--qa" in OS.get_cmdline_user_args():
		call_deferred("_qa")

func _select(index: int) -> void:
	actor.animation_player.stop()
	actor.play_move(selector.get_item_text(index))

func _update_camera() -> void:
	var target := Vector3(0, 0.95, 0)
	if actor and actor.skeleton:
		var hip: Vector3 = (actor.skeleton.global_transform * actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone("Hips"))).origin
		target = hip
	camera.position = target + Vector3(sin(orbit) * distance, 0.7, cos(orbit) * distance)
	camera.look_at(target)

func _process(_delta: float) -> void:
	_update_camera()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		orbit -= event.relative.x * 0.008
		_update_camera()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(2.0, distance - 0.25)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(8.0, distance + 0.25)
		_update_camera()

func _qa() -> void:
	var report := []
	for move in actor.get_moves():
		var animation: Animation = actor.animation_player.get_animation(move)
		actor.animation_player.play(move)
		actor.animation_player.seek(animation.length * 0.45, true)
		actor.animation_player.pause()
		for index in selector.item_count:
			if selector.get_item_text(index) == move:
				selector.select(index)
		await get_tree().process_frame
		_update_camera()
		await RenderingServer.frame_post_draw
		report.append({"name": move, "length": animation.length, "tracks": animation.get_track_count()})
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("res://../../previews/" + move + ".png")
		if move in ["backflip", "front_flip", "crane_kick"] and DisplayServer.get_name() != "headless":
			for frame in 7:
				actor.animation_player.seek(animation.length * frame / 7.0, true)
				await get_tree().process_frame
				_update_camera()
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("res://../../previews/" + move + "_" + str(frame) + ".png")
	print(JSON.stringify(report))
	get_tree().quit()
