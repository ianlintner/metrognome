@tool
extends SceneTree

# Headless rig inspector: dumps skeleton bones + animation tracks for the
# biped gnome hop clip so we can build an arms-down variant.
# Run: Godot --headless --path . --script res://tools/inspect_gnome.gd

func _init() -> void:
	var path := "res://assets/gnome/biped/Meshy_AI_Happy_Garden_Gnome_biped_Animation_Hop_with_Arms_Raised_withSkin.glb"
	var scene := load(path) as PackedScene
	if scene == null:
		print("FAILED to load ", path)
		quit()
		return
	var root := scene.instantiate()

	var skel := _find_skeleton(root)
	if skel != null:
		print("=== SKELETON: ", skel.name, " (", skel.get_bone_count(), " bones) ===")
		for i in skel.get_bone_count():
			print("  [", i, "] ", skel.get_bone_name(i))
	else:
		print("No Skeleton3D found")

	var ap := _find_anim_player(root)
	if ap != null:
		print("=== ANIMATIONPLAYER: ", ap.name, " ===")
		for anim_name in ap.get_animation_list():
			var a := ap.get_animation(anim_name)
			print("  ANIM '", anim_name, "' length=", a.length, " tracks=", a.get_track_count())
			for t in a.get_track_count():
				var tp := a.track_get_path(t)
				var tt := a.track_get_type(t)
				print("    track[", t, "] type=", tt, " path=", tp)
	else:
		print("No AnimationPlayer found")

	quit()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for c in node.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for c in node.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
