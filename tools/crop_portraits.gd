extends SceneTree
## Crops the HEAD DETAIL panel out of each owner character sheet (docs/design/characters/*.webp,
## 1536x1024) into a dialogue / profile portrait at game/ui/portraits/<id>.png.
## Re-run after replacing a sheet:  godot --headless --path . -s res://tools/crop_portraits.gd
## The rects are hand-measured per sheet (x, y, w, h in sheet pixels).

const SHEETS := {
	"wren": ["wren.webp", Rect2i(1122, 93, 194, 226)],
	"elias": ["professor_elias.webp", Rect2i(1057, 53, 241, 282)],
	"varden": ["general_varden.webp", Rect2i(1073, 53, 222, 270)],
	"varrick": ["varrick_silas.webp", Rect2i(1061, 53, 241, 214)],
	"shadow_assassin": ["shadow_assassin.webp", Rect2i(1061, 51, 224, 207)],
	"kellan": ["kellan.webp", Rect2i(1062, 51, 224, 218)],
	"eloi": ["eloi.webp", Rect2i(1051, 53, 231, 220)],
	"nyra": ["nyra.webp", Rect2i(1062, 22, 210, 200)],
	"saevi": ["saevi.webp", Rect2i(1055, 17, 233, 214)],
	"kazren": ["kazren.webp", Rect2i(1058, 23, 233, 212)],
	"lyra": ["lyra.webp", Rect2i(1024, 20, 242, 214)],
	"cael": ["cael.webp", Rect2i(1024, 20, 242, 227)],
}

func _initialize() -> void:
	for id in SHEETS:
		var spec: Array = SHEETS[id]
		var img := Image.load_from_file("res://docs/design/characters/" + String(spec[0]))
		if img == null or img.is_empty():
			print("missing sheet for ", id)
			continue
		var r: Rect2i = spec[1]
		var scale := img.get_width() / 1536.0
		var rr := Rect2i(Vector2i(Vector2(r.position) * scale), Vector2i(Vector2(r.size) * scale))
		var out := img.get_region(rr)
		var err := out.save_png("res://game/ui/portraits/%s.png" % id)
		print(id, " ", img.get_size(), " -> ", rr, " err=", err)
	quit()
