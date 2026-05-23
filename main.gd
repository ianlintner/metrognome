extends Node3D

const GNOME_SPACING := 1.8

var _metronome: Metronome
var _audio_clicker: AudioClicker
var _ui_manager: UIManager
var _camera: Camera3D

var _occupied: Array = []  # of [Vector2, float]
var _anim_players: Array[AnimationPlayer] = []

var _gnomes: Array[GnomePulse] = []
var _gnome_scene: PackedScene

var _opossum: Node3D
var _opossum_target: Vector3
var _opossum_phase: float = 0.0
var _opossum_rng := RandomNumberGenerator.new()


func _is_clear(x: float, z: float, radius: float) -> bool:
	var p := Vector2(x, z)
	for o in _occupied:
		if p.distance_to(o[0]) < radius + float(o[1]):
			return false
	return true


func _ready() -> void:
	_setup_environment()
	_setup_lighting()
	_setup_ground()
	_setup_gnome()
	_setup_mushrooms()
	_setup_animals()
	_setup_audio()
	_setup_metronome()
	_setup_ui()
	_setup_camera()


func _setup_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = Color(0.5, 0.55, 0.4)
	env.ambient_light_energy = 0.7

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.55, 0.85)
	sky_mat.sky_horizon_color = Color(0.6, 0.7, 0.75)
	sky_mat.ground_horizon_color = Color(0.25, 0.35, 0.15)
	sky_mat.ground_bottom_color = Color(0.1, 0.2, 0.05)

	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky

	env.ssao_enabled = true
	env.ssil_enabled = true

	world_env.environment = env
	add_child(world_env)


func _setup_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.8
	sun.light_color = Color(1, 0.95, 0.85)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.1
	sun.directional_shadow_split_2 = 0.3
	add_child(sun)


func _setup_ground() -> void:
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(80, 80)
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.28, 0.08)
	mat.roughness = 0.9
	ground.material_override = mat
	ground.create_trimesh_collision()
	add_child(ground)


func _setup_gnome() -> void:
	_gnome_scene = load("res://assets/gnome/garden_gnome.glb") as PackedScene
	if _gnome_scene == null:
		push_error("Failed to load gnome model from res://assets/gnome/garden_gnome.glb")
		return
	_rebuild_gnome_line(4)


func _rebuild_gnome_line(count: int) -> void:
	for g in _gnomes:
		g.queue_free()
	_gnomes.clear()
	if _gnome_scene == null:
		return

	var total_width := float(count - 1) * GNOME_SPACING
	var start_x := -total_width / 2.0

	for i in count:
		var pulse := GnomePulse.new()
		pulse.name = "Gnome%d" % i
		pulse.position = Vector3(-(start_x + i * GNOME_SPACING), 1.5, 0)
		pulse.base_bounce_height = 0.25
		pulse.accent_bounce_height = 1.2
		add_child(pulse)

		var model := _gnome_scene.instantiate() as Node3D
		model.name = "GnomeModel"
		model.scale = Vector3(1.5, 1.5, 1.5)
		pulse.add_child(model)

		_gnomes.append(pulse)

	_orient_gnomes_to_camera()


func _orient_gnomes_to_camera() -> void:
	if _camera == null:
		return
	for pulse in _gnomes:
		var model := pulse.get_node_or_null("GnomeModel") as Node3D
		if model == null:
			continue
		var target_xz := Vector3(_camera.global_position.x, model.global_position.y, _camera.global_position.z)
		if (target_xz - model.global_position).length_squared() < 0.0001:
			continue
		model.look_at(target_xz, Vector3.UP)
		model.rotate_object_local(Vector3.UP, -PI / 2.0)


func _mushroom_y(path: String, y_off: float, s: float) -> float:
	if "dancing" in path:
		return y_off * s
	if "mushroom.glb" in path and not "mushrooms.glb" in path:
		return y_off + 0.6 * (s - 1.0) + 0.15 * (s - 1.0) * (s - 1.0)
	return y_off


func _giant_mushroom_y(path: String, y_off: float, s: float) -> float:
	if "dancing" in path:
		return y_off * s
	if "mushroom.glb" in path and not "mushrooms.glb" in path:
		return y_off * s + s * 0.48
	return y_off + s * 0.48


func _mushroom_radius(path: String, s: float) -> float:
	return s * 8.0 if "amanita" in path else s * 1.2


func _setup_mushrooms() -> void:
	var forest := Node3D.new()
	forest.name = "MushroomForest"
	add_child(forest)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var kinds: Array = [
		["res://assets/mushrooms/mushroom.glb", 0.6, 3.6, 0.5],
		["res://assets/mushrooms/amanita_muscaria_mushroom.glb", 0.084, 0.504, -0.5],
		["res://assets/mushrooms/dancing_mushroom.glb", 0.6, 3.6, -0.1],
	]
	var loaded: Array = []
	for k in kinds:
		var s := load(k[0]) as PackedScene
		if s != null:
			loaded.append([s, k[1], k[2], k[0], k[3]])
	if loaded.is_empty():
		return

	_occupied.append([Vector2.ZERO, 2.5])

	# Main ring
	var count := 22
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 30:
		attempts += 1
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(9.0, 22.0)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist

		if absf(x) < 3.5 and z < 3.0:
			continue
		if z < 0.0 and absf(x) < 8.0:
			continue
		if z > 0.0 and dist < 14.0:
			continue

		var entry: Array = loaded[placed % loaded.size()]
		var ms: float = rng.randf_range(float(entry[1]), float(entry[2]))
		var path: String = entry[3]
		var radius := _mushroom_radius(path, ms)
		if not _is_clear(x, z, radius + 0.3):
			continue

		placed += 1
		_occupied.append([Vector2(x, z), radius])

		var mushroom := (entry[0] as PackedScene).instantiate() as Node3D
		mushroom.position = Vector3(x, _mushroom_y(path, float(entry[4]), ms), z)
		mushroom.scale = Vector3(ms, ms, ms)
		mushroom.rotate_y(rng.randf_range(0.0, TAU))
		forest.add_child(mushroom)
		_play_first_animation(mushroom)

	# Giants — back hemisphere only
	var giant_count := 6
	var giants_placed := 0
	var giant_attempts := 0
	while giants_placed < giant_count and giant_attempts < giant_count * 40:
		giant_attempts += 1
		var angle := rng.randf_range(0.1, PI - 0.1)
		var dist := rng.randf_range(14.0, 26.0)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist

		var entry: Array = loaded[rng.randi_range(0, loaded.size() - 1)]
		var gs: float = rng.randf_range(float(entry[2]), float(entry[2]) * 3.0)
		var path: String = entry[3]
		var radius := _mushroom_radius(path, gs)
		if not _is_clear(x, z, radius + 0.5):
			continue

		_occupied.append([Vector2(x, z), radius])
		var giant := (entry[0] as PackedScene).instantiate() as Node3D
		giant.position = Vector3(x, _giant_mushroom_y(path, float(entry[4]), gs), z)
		giant.scale = Vector3(gs, gs, gs)
		giant.rotate_y(rng.randf_range(0.0, TAU))
		forest.add_child(giant)
		_play_first_animation(giant)
		giants_placed += 1

	# Horizon ring
	var horizon_count := 18
	var horizon_placed := 0
	var horizon_attempts := 0
	while horizon_placed < horizon_count and horizon_attempts < horizon_count * 30:
		horizon_attempts += 1
		var angle := rng.randf_range(-0.15, PI + 0.15)
		var dist := rng.randf_range(24.0, 30.0)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist

		var entry: Array = loaded[horizon_placed % loaded.size()]
		var hs: float = rng.randf_range(float(entry[1]), float(entry[2]))
		var path: String = entry[3]
		var radius := _mushroom_radius(path, hs)
		if not _is_clear(x, z, radius + 0.3):
			continue

		_occupied.append([Vector2(x, z), radius])
		var distant := (entry[0] as PackedScene).instantiate() as Node3D
		distant.position = Vector3(x, _mushroom_y(path, float(entry[4]), hs), z)
		distant.scale = Vector3(hs, hs, hs)
		distant.rotate_y(rng.randf_range(0.0, TAU))
		forest.add_child(distant)
		_play_first_animation(distant)
		horizon_placed += 1


func _setup_animals() -> void:
	var animals := Node3D.new()
	animals.name = "Animals"
	add_child(animals)

	var rng := RandomNumberGenerator.new()
	rng.seed = 99

	var frog_scene := load("res://assets/animals/frog.glb") as PackedScene
	var opossum_scene := load("res://assets/animals/opossum.glb") as PackedScene

	if frog_scene != null:
		var frog_count := rng.randi_range(3, 6)
		var spawned := 0
		var tries := 0
		while spawned < frog_count and tries < frog_count * 40:
			tries += 1
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(3.5, 8.0)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			if not _is_clear(x, z, 1.8):
				continue
			_occupied.append([Vector2(x, z), 1.8])

			var frog := frog_scene.instantiate() as Node3D
			frog.position = Vector3(x, -0.67, z)
			frog.scale = Vector3.ONE * 3.0
			animals.add_child(frog)
			var cam_pos := Vector3(0, frog.global_position.y, -14)
			if (cam_pos - frog.global_position).length_squared() > 0.0001:
				frog.look_at(cam_pos, Vector3.UP)
				frog.rotate_object_local(Vector3.UP, PI)
				frog.rotate_object_local(Vector3.UP, rng.randf_range(-0.35, 0.35))
			_play_first_animation(frog)
			spawned += 1

	if opossum_scene != null:
		var x := 0.0
		var z := 0.0
		for t in 30:
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(5.0, 7.5)
			x = cos(angle) * dist
			z = sin(angle) * dist
			if _is_clear(x, z, 0.8):
				break
		_occupied.append([Vector2(x, z), 0.8])

		var opossum := opossum_scene.instantiate() as Node3D
		opossum.position = Vector3(x, 0, z)
		opossum.scale = Vector3.ONE * 0.4
		opossum.rotate_y(rng.randf_range(0.0, TAU))
		animals.add_child(opossum)
		_play_first_animation(opossum)

		_opossum = opossum
		_opossum_rng.seed = 1337
		_pick_opossum_target()


func _pick_opossum_target() -> void:
	for t in 25:
		var a := _opossum_rng.randf_range(0.0, TAU)
		var d := _opossum_rng.randf_range(5.0, 14.0)
		var x: float = cos(a) * d
		var z: float = sin(a) * d
		if sqrt(x * x + z * z) < 4.0:
			continue
		_opossum_target = Vector3(x, _opossum.position.y, z)
		return
	_opossum_target = Vector3(8, _opossum.position.y, 8)


func _process(delta: float) -> void:
	if _opossum == null or _metronome == null or not _metronome.is_playing():
		return

	var pos := _opossum.position
	var to_target := _opossum_target - pos
	to_target.y = 0.0
	if to_target.length() < 0.5:
		_pick_opossum_target()
		return

	var dir := to_target.normalized()
	_opossum_phase += delta * 0.7
	var curve := sin(_opossum_phase) * 0.35
	var heading := dir.rotated(Vector3.UP, curve)
	var speed := 1.1
	var step := heading * speed * delta
	var new_pos := pos + step
	_opossum.position = Vector3(new_pos.x, pos.y, new_pos.z)

	var look := _opossum.position + heading
	if (look - _opossum.position).length_squared() > 0.0001:
		_opossum.look_at(look, Vector3.UP)
		_opossum.rotate_object_local(Vector3.UP, PI)


func _play_first_animation(root: Node) -> void:
	var anim := _find_animation_player(root)
	if anim != null and anim.get_animation_list().size() > 0:
		var anim_name: String = anim.get_animation_list()[0]
		var a := anim.get_animation(anim_name)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play(anim_name)
		anim.pause()
		_anim_players.append(anim)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _setup_audio() -> void:
	_audio_clicker = AudioClicker.new()
	_audio_clicker.name = "AudioClicker"
	add_child(_audio_clicker)


func _setup_metronome() -> void:
	_metronome = Metronome.new()
	_metronome.name = "Metronome"
	_metronome.bpm = 120
	_metronome.beats_per_measure = 4
	add_child(_metronome)


func _setup_ui() -> void:
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "UICanvasLayer"
	add_child(canvas_layer)

	_ui_manager = UIManager.new()
	_ui_manager.name = "UI"
	canvas_layer.add_child(_ui_manager)

	_ui_manager.bpm_changed.connect(_on_ui_bpm_changed)
	_ui_manager.time_signature_changed.connect(_on_ui_time_signature_changed)
	_ui_manager.volume_changed.connect(_on_ui_volume_changed)
	_ui_manager.sound_changed.connect(_on_ui_sound_changed)
	_ui_manager.accent_mode_changed.connect(_on_ui_accent_mode_changed)
	_ui_manager.play_toggled.connect(_on_ui_play_toggled)
	_metronome.tick.connect(_on_metronome_tick)


func _on_ui_bpm_changed(bpm: int) -> void:
	_metronome.bpm = bpm


func _on_ui_time_signature_changed(beats: int, unit: int) -> void:
	_metronome.set_time_signature(beats, unit)
	_rebuild_gnome_line(beats)


func _on_ui_volume_changed(vol: float) -> void:
	_audio_clicker.volume = vol


func _on_ui_sound_changed(sound_type: int) -> void:
	_audio_clicker.set_sound_type(sound_type)


func _on_ui_accent_mode_changed(mode: int) -> void:
	_metronome.set_accent_mode(mode)


func _on_ui_play_toggled(playing: bool) -> void:
	if playing:
		_metronome.play()
	else:
		_metronome.pause()
	for ap in _anim_players:
		if playing:
			ap.play()
		else:
			ap.pause()


func _on_metronome_tick(beat: int, total_beats: int, is_accent: bool) -> void:
	if is_accent:
		_audio_clicker.play_accent()
	else:
		_audio_clicker.play_click()
	if beat >= 0 and beat < _gnomes.size():
		_gnomes[beat].on_tick(is_accent)
	_ui_manager.on_tick(beat, total_beats)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 70
	add_child(_camera)
	_camera.position = Vector3(0, 5.0, -14)
	_camera.look_at(Vector3(0, 1.4, 0))
	_orient_gnomes_to_camera()
