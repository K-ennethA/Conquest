extends SceneTree

## Renders assets/branding/splash.svg to splash.png. Godot's boot_splash/image
## setting ONLY accepts PNG (discovered at gate: "The only supported format is
## PNG"), so the authored SVG is rasterized once here and project.godot points
## at the PNG. Re-run after editing the SVG:
##   godot --headless -s dev_scripts/render_splash_png.gd
## No autoload/game-class references: safe as a -s main-loop script.

const SVG_PATH := "res://assets/branding/splash.svg"
const PNG_PATH := "res://assets/branding/splash.png"


func _initialize() -> void:
	var f: FileAccess = FileAccess.open(SVG_PATH, FileAccess.READ)
	if f == null:
		printerr("[SPLASH] cannot open %s" % SVG_PATH)
		quit(1)
		return
	var svg_text: String = f.get_as_text()
	f.close()

	var img: Image = Image.new()
	var err: int = img.load_svg_from_string(svg_text, 1.0)
	if err != OK:
		printerr("[SPLASH] SVG rasterize failed: %d" % err)
		quit(1)
		return

	err = img.save_png(PNG_PATH)
	if err != OK:
		printerr("[SPLASH] PNG save failed: %d" % err)
		quit(1)
		return

	print("[SPLASH] DONE %s (%dx%d)" % [PNG_PATH, img.get_width(), img.get_height()])
	quit(0)
