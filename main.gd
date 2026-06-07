extends Node3D

const GNOME_SPACING := 1.8
const SPAWN_OPOSSUM := false  # roaming opossum was an animation MVP test; off for now

# Beat-indexed hop tuning.
const GNOME_HOP := "hop"          # library key for the arms-down hop clip
const HOP_BEATS := 1.0            # beats one full hop spans (smaller = snappier)
const LIFT_THRESHOLD := 0.1       # min relative Hips lift to count as a real jump
const NODE_BOUNCE_HEIGHT := 0.65  # parabola height when the skeleton doesn't jump
const NODE_BOUNCE_DURATION := 0.26
const ARM_BONES := [              # bones we neutralise to an arms-down pose
	"LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
	"RightShoulder", "RightArm", "RightForeArm", "RightHand",
]

# Character catalog. Every entry is a Meshy biped sharing the same rig, so the
# arms-down hop technique applies uniformly. Add a character = add a row here.
#   model:     GLB instanced for the line — must contain the rig + hop clip
#   hop_clip:  name-substring of the hop animation inside `model`
#   idle_glb:  GLB containing the idle pose (may equal `model` for merged exports)
#   idle_clip: name-substring of the idle animation whose arm pose we graft on
#   icon:      neutral GLB rendered to the selector thumbnail
#   scale:     per-character size tuning (different native scales)
const CHARACTERS := [
	{
		"id": "gnome",
		"name": "Gnome",
		"model": "res://assets/gnome/biped/Meshy_AI_Happy_Garden_Gnome_biped_Animation_Hop_with_Arms_Raised_withSkin.glb",
		"hop_clip": "Hop_with_Arms_Raised",
		"idle_glb": "res://assets/gnome/biped/Meshy_AI_Happy_Garden_Gnome_biped_Animation_Idle_3_withSkin.glb",
		"idle_clip": "Idle_3",
		"icon": "res://assets/gnome/biped/Meshy_AI_Happy_Garden_Gnome_biped_Character_output.glb",
		"scale": 1.6,
	},
	{
		"id": "frog",
		"name": "Frog",
		"model": "res://assets/frog_biped/Meshy_AI_Low_poly_cartoon_frog_biped_Animation_Hop_with_Arms_Raised_withSkin.glb",
		"hop_clip": "Hop_with_Arms_Raised",
		"idle_glb": "res://assets/frog_biped/Meshy_AI_Low_poly_cartoon_frog_biped_Animation_Idle_3_withSkin.glb",
		"idle_clip": "Idle_3",
		"icon": "res://assets/frog_biped/Meshy_AI_Low_poly_cartoon_frog_biped_Character_output.glb",
		"scale": 1.6,
	},
	{
		"id": "beaver",
		"name": "Beaver",
		# Beaver ships all clips merged into one GLB, so model and idle share it.
		"model": "res://assets/beaver_biped/Meshy_AI_Low_Poly_Beaver_biped_Meshy_AI_Meshy_Merged_Animations.glb",
		"hop_clip": "Hop_with_Arms_Raised",
		"idle_glb": "res://assets/beaver_biped/Meshy_AI_Low_Poly_Beaver_biped_Meshy_AI_Meshy_Merged_Animations.glb",
		"idle_clip": "Idle_3",
		"icon": "res://assets/beaver_biped/Meshy_AI_Low_Poly_Beaver_biped_Character_output.glb",
		"scale": 1.6,
	},
]

var _metronome: Metronome
var _audio_clicker: AudioClicker
var _ui_manager: UIManager
var _camera: Camera3D

var _occupied: Array = []  # of [Vector2, float]
var _anim_players: Array[AnimationPlayer] = []

var _gnomes: Array[GnomePulse] = []
var _gnome_scene: PackedScene
var _gnome_anim_players: Array[AnimationPlayer] = []  # index-aligned with _gnomes
var _hop_anim: Animation  # arms-down hop for the active character
var _swayers: Array[MushroomSway] = []  # dancing mushrooms pulsed on the beat
var _hop_uses_node_bounce: bool = false  # true when the clip has no real lift
var _active_char: int = 0  # index into CHARACTERS
var _line_count: int = 4   # current beats-per-measure (gnome line length)

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
	_populate_character_selector()


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

	# Atmospheric depth fog — fades the far treeline into a green haze and masks
	# the skybox horizon, so it reads as a clearing deep inside a forest.
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = Color(0.55, 0.68, 0.55)
	env.fog_light_energy = 1.0
	env.fog_sky_affect = 0.5
	env.fog_depth_begin = 22.0
	env.fog_depth_end = 70.0
	env.fog_depth_curve = 0.7

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
	ground_mesh.size = Vector2(170, 170)  # extends under the far treeline
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	ground.mesh = ground_mesh
	var mat := StandardMaterial3D.new()
	var grass := load("res://assets/forest/grass_texture.png") as Texture2D
	if grass != null:
		mat.albedo_texture = grass
		mat.uv1_scale = Vector3(26, 26, 1)  # ~6.5 units per tile across the ground
		mat.albedo_color = Color(0.95, 1.0, 0.92)
	else:
		mat.albedo_color = Color(0.12, 0.28, 0.08)
	mat.roughness = 1.0
	ground.material_override = mat
	ground.create_trimesh_collision()
	add_child(ground)


func _setup_gnome() -> void:
	_load_active_character()
	_rebuild_gnome_line(_line_count)


func _load_active_character() -> void:
	# Build the active character's model scene + arms-down hop clip.
	# Model carries the rigged skeleton + AnimationPlayer; we swap in our own
	# arms-down clip built from the named hop + idle animations.
	var c: Dictionary = CHARACTERS[_active_char]
	_gnome_scene = load(c.model) as PackedScene
	if _gnome_scene == null:
		push_error("Failed to load character model from " + str(c.model))
		return
	_hop_anim = _build_arms_down_hop(String(c.hop_clip), String(c.idle_glb), String(c.idle_clip))
	# If the clip barely lifts the hips, the skeleton doesn't really jump — fall
	# back to a clean GnomePulse node parabola for a visible, consistent hop.
	_hop_uses_node_bounce = _hop_anim == null or _hop_relative_lift(_hop_anim) < LIFT_THRESHOLD


func set_active_character(index: int) -> void:
	# Swap the whole gnome line to a different character, keeping the beat count.
	if index < 0 or index >= CHARACTERS.size() or index == _active_char:
		return
	_active_char = index
	_load_active_character()
	_rebuild_gnome_line(_line_count)


func _rebuild_gnome_line(count: int) -> void:
	_line_count = count
	for g in _gnomes:
		g.queue_free()
	_gnomes.clear()
	_gnome_anim_players.clear()
	if _gnome_scene == null:
		return

	var char_scale: float = float(CHARACTERS[_active_char].scale)
	var total_width := float(count - 1) * GNOME_SPACING
	var start_x := -total_width / 2.0

	# When the skeletal clip doesn't lift, the node parabola provides the jump.
	var node_bounce := NODE_BOUNCE_HEIGHT if _hop_uses_node_bounce else 0.0

	for i in count:
		var pulse := GnomePulse.new()
		pulse.name = "Gnome%d" % i
		pulse.position = Vector3(-(start_x + i * GNOME_SPACING), 0.0, 0)
		pulse.base_bounce_height = node_bounce
		pulse.accent_bounce_height = node_bounce
		pulse.bounce_duration = NODE_BOUNCE_DURATION
		add_child(pulse)

		var model := _gnome_scene.instantiate() as Node3D
		model.name = "GnomeModel"
		model.scale = Vector3(char_scale, char_scale, char_scale)
		pulse.add_child(model)

		# Give this gnome's player the arms-down hop, then rest it on frame 0 so
		# the model stands relaxed (arms down) instead of snapping to bind pose.
		var ap := _find_animation_player(model)
		if ap != null and _hop_anim != null:
			var lib := ap.get_animation_library("")
			if lib == null:
				lib = AnimationLibrary.new()
				ap.add_animation_library("", lib)
			if not lib.has_animation(GNOME_HOP):
				lib.add_animation(GNOME_HOP, _hop_anim)
			ap.play(GNOME_HOP)
			ap.seek(0.0, true)
			ap.pause()
		_gnome_anim_players.append(ap)

		_gnomes.append(pulse)

	_orient_gnomes_to_camera()
	_sync_gnome_anim_to_bpm()


func _sync_gnome_anim_to_bpm() -> void:
	# Compress the hop so it spans HOP_BEATS beats: faster BPM -> faster hop.
	# speed_scale = clip_length / (beat_period * HOP_BEATS), beat_period = 60 / bpm.
	if _metronome == null or _hop_anim == null or _hop_anim.length <= 0.0:
		return
	var beat_period := 60.0 / float(_metronome.bpm)
	var s := _hop_anim.length / (beat_period * HOP_BEATS)
	for ap in _gnome_anim_players:
		if ap != null:
			ap.speed_scale = s


func _build_arms_down_hop(hop_clip: String, idle_path: String, idle_clip: String) -> Animation:
	# Take the well-timed hop clip and overwrite only the arm-bone tracks with a
	# relaxed arms-down pose sampled from the idle clip. Legs/hips/spine untouched.
	var hop_player := _find_animation_player(_gnome_scene.instantiate())
	if hop_player == null:
		push_error("Model GLB has no AnimationPlayer")
		return null
	var hop_name := _find_clip(hop_player, hop_clip)
	if hop_name.is_empty():
		push_error("Hop clip '%s' not found in model" % hop_clip)
		_free_temp_root(hop_player)
		return null
	var src := hop_player.get_animation(hop_name)
	var anim := src.duplicate(true) as Animation

	var idle_rot := _sample_idle_arm_rotations(idle_path, idle_clip)

	for t in anim.get_track_count():
		var bone := String(anim.track_get_path(t)).get_slice(":", 1)
		if not (bone in ARM_BONES):
			continue
		var kind := anim.track_get_type(t)
		# Collapse the track to a single constant key (no arm animation).
		var first_val: Variant = anim.track_get_key_value(t, 0)
		if kind == Animation.TYPE_ROTATION_3D and idle_rot.has(bone):
			first_val = idle_rot[bone]
		while anim.track_get_key_count(t) > 0:
			anim.track_remove_key(t, 0)
		anim.track_insert_key(t, 0.0, first_val)

	anim.loop_mode = Animation.LOOP_NONE
	hop_player.owner = null  # detach so we can free the temp instance
	_free_temp_root(hop_player)
	return anim


func _sample_idle_arm_rotations(idle_path: String, idle_clip: String) -> Dictionary:
	# Returns {bone_name: Quaternion} for arm bones at the idle clip's first key.
	var out := {}
	var idle_scene := load(idle_path) as PackedScene
	if idle_scene == null:
		return out
	var idle_player := _find_animation_player(idle_scene.instantiate())
	if idle_player == null:
		return out
	var idle_name := _find_clip(idle_player, idle_clip)
	if idle_name.is_empty():
		_free_temp_root(idle_player)
		return out
	var a := idle_player.get_animation(idle_name)
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_ROTATION_3D:
			continue
		var bone := String(a.track_get_path(t)).get_slice(":", 1)
		if bone in ARM_BONES:
			out[bone] = a.track_get_key_value(t, 0)
	_free_temp_root(idle_player)
	return out


func _find_clip(player: AnimationPlayer, substr: String) -> StringName:
	# First animation whose name contains `substr` (handles both one-clip GLBs
	# and merged GLBs with many named clips).
	for n in player.get_animation_list():
		if substr in String(n):
			return n
	return &""


func _free_temp_root(node: Node) -> void:
	# Walk to the topmost parent of a temp (not-in-tree) instance and free it.
	var root := node
	while root.get_parent() != null:
		root = root.get_parent()
	root.free()


var _icon_viewports: Array[SubViewport] = []


func _populate_character_selector() -> void:
	# Build a live thumbnail per character and hand the strip to the UI. We render
	# a few warmup frames, then freeze each viewport so it stops costing GPU time
	# while the ViewportTexture keeps its last frame.
	var items: Array = []
	for c in CHARACTERS:
		var tex := _render_character_icon(String(c.icon))
		items.append({"name": String(c.name), "icon": tex})
	if _ui_manager != null:
		_ui_manager.set_characters(items, _active_char)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for sub in _icon_viewports:
		if is_instance_valid(sub):
			sub.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _render_character_icon(glb_path: String) -> Texture2D:
	# Render a neutral character GLB to a transparent thumbnail via a SubViewport.
	# Fixed framing tuned for a ~1.7m biped with feet at the origin (the whole
	# catalog is Meshy bipeds), which is far more reliable than AABB auto-framing
	# on skinned meshes.
	var scene := load(glb_path) as PackedScene
	if scene == null:
		return null

	var sub := SubViewport.new()
	sub.size = Vector2i(220, 240)
	sub.transparent_bg = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Isolated world with bright ambient so albedo reads well at thumbnail size.
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.86, 0.9)
	env.ambient_light_energy = 1.6
	var world := World3D.new()
	world.environment = env
	sub.world_3d = world
	add_child(sub)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 35, 0)
	key.light_energy = 1.5
	sub.add_child(key)

	var model := scene.instantiate() as Node3D
	sub.add_child(model)

	# Camera in front of the model's face (these Meshy bipeds face +Z), slight
	# 3/4 angle, framing head-to-toe.
	var look := Vector3(0.0, 0.95, 0.0)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.position = Vector3(0.45, 1.05, 2.9)
	sub.add_child(cam)
	cam.look_at(look, Vector3.UP)
	cam.current = true

	_icon_viewports.append(sub)
	return sub.get_texture()


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
		model.rotate_object_local(Vector3.UP, PI)


const FOREST_DIR := "res://assets/forest/"
# Meshy models are normalized to a ~2-unit bounding box centered at the origin,
# so an item at `scale` is ~2*scale tall and rests on the ground when its center
# is raised by `scale` (half its height).


func _forest_scene(name: String) -> PackedScene:
	return load(FOREST_DIR + name + ".glb") as PackedScene


func _place_forest(parent: Node3D, scene: PackedScene, x: float, z: float, s: float, dancing: bool, rng: RandomNumberGenerator) -> void:
	if scene == null:
		return
	var model := scene.instantiate() as Node3D
	model.scale = Vector3(s, s, s)
	model.rotate_y(rng.randf_range(0.0, TAU))
	if dancing:
		# Sway pivots at the base (ground); model centered at +half-height.
		var sway := MushroomSway.new()
		sway.position = Vector3(x, 0.0, z)
		model.position = Vector3(0.0, s, 0.0)
		sway.add_child(model)
		parent.add_child(sway)
		_swayers.append(sway)
	else:
		model.position = Vector3(x, s, z)
		parent.add_child(model)


func _setup_mushrooms() -> void:
	var forest := Node3D.new()
	forest.name = "Forest"
	add_child(forest)

	var rng := RandomNumberGenerator.new()
	rng.seed = 42

	var toadstool := _forest_scene("mushroom_toadstool")
	var tall := _forest_scene("mushroom_tall")
	var cluster := _forest_scene("mushroom_cluster")
	var fern := _forest_scene("fern_plant")

	# Tree pool — variants are included automatically once generated/imported.
	var trees: Array = []
	for n in ["forest_tree", "tree_round", "tree_pine"]:
		var t := _forest_scene(n)
		if t != null:
			trees.append(t)
	var bush := _forest_scene("bush_shrub")

	# Reserve the central stage where the character line stands.
	_occupied.append([Vector2.ZERO, 3.0])

	# --- Mid trees: a ring framing the grove (behind + sides) ---
	if not trees.is_empty():
		var placed := 0
		var tries := 0
		while placed < 14 and tries < 14 * 50:
			tries += 1
			var angle := rng.randf_range(-0.3, PI + 0.3)  # back hemisphere + sides
			var dist := rng.randf_range(16.0, 30.0)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			var s := rng.randf_range(3.5, 5.5)
			if not _is_clear(x, z, s * 1.4):
				continue
			_occupied.append([Vector2(x, z), s * 1.2])
			_place_forest(forest, trees[rng.randi() % trees.size()], x, z, s, false, rng)
			placed += 1

		# --- Dense background treeline: a wall of trees masking the skybox ---
		var wall := 44
		var wtries := 0
		var wplaced := 0
		while wplaced < wall and wtries < wall * 30:
			wtries += 1
			var angle := rng.randf_range(0.0, TAU)
			var dist := rng.randf_range(34.0, 60.0)
			var x: float = cos(angle) * dist
			var z: float = sin(angle) * dist
			var s := rng.randf_range(5.0, 8.0)  # large, fade into fog
			if not _is_clear(x, z, s * 1.0):
				continue
			_occupied.append([Vector2(x, z), s * 0.9])
			_place_forest(forest, trees[rng.randi() % trees.size()], x, z, s, false, rng)
			wplaced += 1

		# --- Bushes filling the treeline base ---
		if bush != null:
			var bplaced := 0
			var btries := 0
			while bplaced < 24 and btries < 24 * 30:
				btries += 1
				var angle := rng.randf_range(0.0, TAU)
				var dist := rng.randf_range(28.0, 56.0)
				var x: float = cos(angle) * dist
				var z: float = sin(angle) * dist
				var s := rng.randf_range(1.5, 3.0)
				if not _is_clear(x, z, s * 0.7):
					continue
				_occupied.append([Vector2(x, z), s * 0.6])
				_place_forest(forest, bush, x, z, s, false, rng)
				bplaced += 1

	# --- Mushroom grove around the stage (tall + toadstool dance) ---
	var grove: Array = [toadstool, tall, cluster]
	var gi := 0
	var gplaced := 0
	var gtries := 0
	while gplaced < 18 and gtries < 18 * 40:
		gtries += 1
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(6.0, 16.0)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		# Keep the front-center sightline to the characters clear.
		if z < 0.0 and absf(x) < 7.0:
			continue
		var scene: PackedScene = grove[gi % grove.size()]
		gi += 1
		if scene == null:
			continue
		var s := rng.randf_range(1.2, 2.4)
		if not _is_clear(x, z, s * 0.9):
			continue
		_occupied.append([Vector2(x, z), s * 0.8])
		var dancing := scene != cluster and rng.randf() < 0.6
		_place_forest(forest, scene, x, z, s, dancing, rng)
		gplaced += 1

	# --- Ground cover: ferns + small mushroom clusters ---
	var cover: Array = [fern, cluster]
	var ci := 0
	var cplaced := 0
	var ctries := 0
	while cplaced < 16 and ctries < 16 * 40:
		ctries += 1
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(5.0, 18.0)
		var x: float = cos(angle) * dist
		var z: float = sin(angle) * dist
		if z < 0.0 and absf(x) < 6.0:
			continue
		var scene: PackedScene = cover[ci % cover.size()]
		ci += 1
		if scene == null:
			continue
		var s := rng.randf_range(0.7, 1.3)
		if not _is_clear(x, z, s * 0.6):
			continue
		_occupied.append([Vector2(x, z), s * 0.5])
		_place_forest(forest, scene, x, z, s, false, rng)
		cplaced += 1


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

	if SPAWN_OPOSSUM and opossum_scene != null:
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


func _play_first_animation(root: Node) -> AnimationPlayer:
	var anim := _find_animation_player(root)
	if anim != null and anim.get_animation_list().size() > 0:
		var anim_name: String = anim.get_animation_list()[0]
		var a := anim.get_animation(anim_name)
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play(anim_name)
		anim.pause()
		_anim_players.append(anim)
		return anim
	return null


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
	_sync_gnome_anim_to_bpm()


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
	_ui_manager.character_changed.connect(set_active_character)
	_metronome.tick.connect(_on_metronome_tick)


func _on_ui_bpm_changed(bpm: int) -> void:
	_metronome.bpm = bpm
	_sync_gnome_anim_to_bpm()


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
	# Dancing mushrooms only animate while playing; frozen otherwise.
	for sway in _swayers:
		sway.set_playing(playing)


func _on_metronome_tick(beat: int, total_beats: int, is_accent: bool) -> void:
	if is_accent:
		_audio_clicker.play_accent()
	else:
		_audio_clicker.play_click()
	if beat >= 0 and beat < _gnomes.size():
		_gnomes[beat].on_tick(is_accent)
	_hop_gnome(beat)
	for sway in _swayers:
		sway.pulse()  # dancing mushrooms hop on every beat
	_ui_manager.on_tick(beat, total_beats)


func _hop_gnome(beat: int) -> void:
	# Beat-indexed: gnome N hops on beat N (a wave down the line). The node-bounce
	# jump is driven by GnomePulse.on_tick; the skeleton just stays at its relaxed
	# rest pose for those characters.
	if _hop_uses_node_bounce:
		return
	if beat < 0 or beat >= _gnome_anim_players.size():
		return
	var ap := _gnome_anim_players[beat]
	if ap == null:
		return
	ap.play(GNOME_HOP)
	ap.seek(0.0, true)  # force restart even if a prior hop is still playing


func _hop_relative_lift(anim: Animation) -> float:
	# Scale-independent measure of how much the Hips rise during the hop:
	# (Y amplitude) / (mean Y). ~0.5 for a real jump, ~0.02 for a flat clip.
	var trk := -1
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_POSITION_3D and "Hips" in String(anim.track_get_path(t)):
			trk = t
			break
	if trk < 0:
		return 0.0
	var ymin := INF
	var ymax := -INF
	var ysum := 0.0
	var n := 40
	for i in n + 1:
		var v: Vector3 = anim.position_track_interpolate(trk, anim.length * float(i) / float(n))
		ymin = minf(ymin, v.y)
		ymax = maxf(ymax, v.y)
		ysum += v.y
	var mean: float = absf(ysum / float(n + 1))
	return (ymax - ymin) / maxf(0.001, mean)


func _setup_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.fov = 70
	add_child(_camera)
	_camera.position = Vector3(0, 5.0, -14)
	_camera.look_at(Vector3(0, 1.4, 0))
	_orient_gnomes_to_camera()
