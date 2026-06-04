@tool
extends SceneTree

# Composites the cut-out gnome onto a branded gradient to produce:
#   icon_1024.png        full-bleed opaque master (iOS + Android legacy source)
#   adaptive_bg_432.png  gradient-only Android adaptive background
#   adaptive_fg_432.png  gnome in the adaptive safe zone (transparent)
#   splash_logo.png      transparent gnome for the boot splash
# Run: Godot --headless --path . --script res://tools/make_icons.gd

const TOP := Color(0.36, 0.62, 0.88)     # sky blue
const BOTTOM := Color(0.34, 0.58, 0.24)  # grass green
const DIR := "res://assets/branding/"


func _init() -> void:
	var gnome := Image.load_from_file(DIR + "gnome_cutout.png")
	gnome.convert(Image.FORMAT_RGBA8)
	# Tight-crop to the gnome's actual pixels for clean centering.
	var used := gnome.get_used_rect()
	gnome = gnome.get_region(used)
	var aspect := float(gnome.get_width()) / float(gnome.get_height())

	# --- Master icon: full-bleed gradient, gnome ~84% height, centered ---
	var master := _gradient(1024, 1024)
	_blend_centered(master, gnome, aspect, 1024, 1024, 0.84, 0.50)
	master.save_png(DIR + "icon_1024.png")

	# --- Android adaptive background (gradient only) ---
	_gradient(432, 432).save_png(DIR + "adaptive_bg_432.png")

	# --- Android adaptive foreground (gnome inside ~62% safe zone) ---
	var fg := Image.create(432, 432, false, Image.FORMAT_RGBA8)
	fg.fill(Color(0, 0, 0, 0))
	_blend_centered(fg, gnome, aspect, 432, 432, 0.62, 0.46)
	fg.save_png(DIR + "adaptive_fg_432.png")

	# --- Splash logo (transparent gnome, used by the engine boot splash) ---
	var logo := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	logo.fill(Color(0, 0, 0, 0))
	_blend_centered(logo, gnome, aspect, 1024, 1024, 0.78, 0.5)
	logo.save_png(DIR + "splash_logo.png")

	# --- iOS launch logo: smaller gnome with padding so the storyboard centers
	# it at a modest size instead of filling the screen ---
	var launch := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	launch.fill(Color(0, 0, 0, 0))
	_blend_centered(launch, gnome, aspect, 1024, 1024, 0.42, 0.5)
	launch.save_png(DIR + "ios/launch_3x.png")
	var launch2x := launch.duplicate() as Image
	launch2x.resize(683, 683, Image.INTERPOLATE_LANCZOS)
	launch2x.save_png(DIR + "ios/launch_2x.png")

	print("icons written to ", DIR)
	quit()


func _gradient(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		img.fill_rect(Rect2i(0, y, w, 1), TOP.lerp(BOTTOM, float(y) / float(h - 1)))
	return img


func _blend_centered(dst: Image, src: Image, aspect: float, w: int, h: int, height_frac: float, y_center_frac: float) -> void:
	var th := int(h * height_frac)
	var tw := int(th * aspect)
	if tw > int(w * 0.94):
		tw = int(w * 0.94)
		th = int(tw / aspect)
	var scaled := src.duplicate() as Image
	scaled.resize(tw, th, Image.INTERPOLATE_LANCZOS)
	var ox := int((w - tw) / 2.0)
	var oy := int(h * y_center_frac - th / 2.0)
	dst.blend_rect(scaled, Rect2i(0, 0, tw, th), Vector2i(ox, oy))
