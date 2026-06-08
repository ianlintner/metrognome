extends Node

# Off-screen App Store screenshot capture. Instances Main.tscn into a SubViewport
# sized to each exact App Store dimension (the game's UI is a CanvasLayer child of
# Main, so it renders into the SubViewport too), sets character / day-night / play
# state, and saves a PNG. Run with the real GPU:
#   /Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/shot.tscn

const SHOTS := [
	# iPhone 6.5" — 1284 x 2778 (matches App Store Connect's iPhone slot)
	{"f": "iphone-1-gnome-night", "w": 1284, "h": 2778, "char": 0, "night": true,  "play": true},
	{"f": "iphone-2-frog-night",  "w": 1284, "h": 2778, "char": 1, "night": true,  "play": true},
	{"f": "iphone-3-beaver-day",  "w": 1284, "h": 2778, "char": 2, "night": false, "play": true},
	# iPad 13" — 2064 x 2752
	{"f": "ipad-1-gnome-night",   "w": 2064, "h": 2752, "char": 0, "night": true,  "play": true},
	{"f": "ipad-2-frog-day",      "w": 2064, "h": 2752, "char": 1, "night": false, "play": true},
]


func _ready() -> void:
	var out_dir := OS.get_user_data_dir() + "/shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	for c in SHOTS:
		await _capture(c, out_dir)
	print("SHOTS_DONE dir=", out_dir)
	get_tree().quit()


func _capture(c: Dictionary, out_dir: String) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(int(c.w), int(c.h))
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.handle_input_locally = false
	add_child(sv)

	var main: Node = (load("res://Main.tscn") as PackedScene).instantiate()
	sv.add_child(main)
	# Let Main._ready build the scene (forest, characters, UI).
	await get_tree().create_timer(0.6).timeout

	# Drop the title splash overlay so it isn't in the shot.
	var splash: Node = main.get_node_or_null("TitleSplash")
	if splash != null:
		splash.free()

	# Apply the requested state via Main's public methods.
	if int(c.char) != 0:
		main.set_active_character(int(c.char))
	main._apply_time_of_day(bool(c.night))
	main._on_ui_play_toggled(bool(c.play))

	# Let glow/fireflies/animation settle, then grab a frame.
	await get_tree().create_timer(1.4).timeout
	await RenderingServer.frame_post_draw

	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)  # drop alpha — App Store wants opaque
	var path := out_dir + "/" + String(c.f) + ".png"
	img.save_png(path)
	print("SAVED ", path, " ", img.get_width(), "x", img.get_height())

	main.queue_free()
	sv.queue_free()
	await get_tree().process_frame
