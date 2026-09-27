class_name MenuBackdrop
extends Control

## Atmospheric full-screen background shared by every out-of-battle screen: a deep
## navy vertical gradient, a warm gold glow and a cool counter-glow, slow drifting
## gold motes and pale-green grove spores, an edge vignette, and gilded vine
## flourishes in the four corners (the "illuminated grove" page border). Pure
## presentation, ignores the mouse, and costs a handful of TextureRects, two
## CPUParticles2D and one cached _draw.
##
## Add it as the FIRST child of a screen (MenuKit.build_page does this). Set
## [member motes] false before adding it for a static background.

@export var motes: bool = true
## Vignette strength (0..1) -- the main menu raises it over its 3D diorama.
@export var vignette_strength: float = 0.6
## Draw the solid gradient ground. The main menu turns this off so its 3D diorama
## shows through and only the glows / motes / vignette are layered on top.
@export var solid: bool = true
## Gilded vine flourishes in the page corners.
@export var flourishes: bool = true

var _particles: CPUParticles2D
var _spores: CPUParticles2D


func _ready() -> void:
	name = "Backdrop" if name.begins_with("@") else name
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	show_behind_parent = false

	if solid:
		_add_texture(_linear(MenuTheme.BG, MenuTheme.BG_DEEP))
	_add_texture(_radial(Color(MenuTheme.GOLD.r, MenuTheme.GOLD.g, MenuTheme.GOLD.b, 0.13),
		Vector2(0.18, 0.0), Vector2(0.95, 0.9)))
	_add_texture(_radial(Color(MenuTheme.ACCENT.r, MenuTheme.ACCENT.g, MenuTheme.ACCENT.b, 0.07),
		Vector2(0.95, 1.0), Vector2(0.2, 0.2)))
	if motes:
		_add_motes()
	_add_texture(_vignette(vignette_strength))
	if flourishes:
		var f := GroveFlourish.new()
		f.name = "Flourishes"
		f.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(f)
	resized.connect(_on_resized)
	_on_resized()


func _add_texture(tex: Texture2D) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	return tr


static func _linear(top: Color, bottom: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 8
	tex.height = 256
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	return tex


static func _radial(color: Color, center: Vector2, edge: Vector2) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, color)
	g.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = center
	tex.fill_to = edge
	return tex


static func _vignette(strength: float) -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([
		Color(0, 0, 0, 0.0),
		Color(0, 0, 0, 0.12 * strength),
		Color(0, 0, 0, 0.85 * strength),
	])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.width = 256
	tex.height = 256
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 1.05)
	return tex


func _add_motes() -> void:
	_particles = CPUParticles2D.new()
	_particles.name = "Motes"
	_particles.amount = 38
	_particles.lifetime = 14.0
	_particles.preprocess = 14.0
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_particles.direction = Vector2(0.15, -1.0)
	_particles.spread = 18.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 22.0
	_particles.initial_velocity_max = 48.0
	_particles.scale_amount_min = 1.5
	_particles.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.2, 0.8, 1.0])
	ramp.colors = PackedColorArray([
		Color(MenuTheme.GOLD_LITE.r, MenuTheme.GOLD_LITE.g, MenuTheme.GOLD_LITE.b, 0.0),
		Color(MenuTheme.GOLD_LITE.r, MenuTheme.GOLD_LITE.g, MenuTheme.GOLD_LITE.b, 0.55),
		Color(MenuTheme.GOLD.r, MenuTheme.GOLD.g, MenuTheme.GOLD.b, 0.35),
		Color(MenuTheme.GOLD.r, MenuTheme.GOLD.g, MenuTheme.GOLD.b, 0.0),
	])
	_particles.color_ramp = ramp
	add_child(_particles)

	# Grove spores: fewer, slower, pale green, drifting with a slight sway.
	_spores = _particles.duplicate() as CPUParticles2D
	_spores.name = "Spores"
	_spores.amount = 16
	_spores.lifetime = 18.0
	_spores.preprocess = 18.0
	_spores.initial_velocity_min = 10.0
	_spores.initial_velocity_max = 26.0
	_spores.spread = 35.0
	_spores.scale_amount_min = 1.2
	_spores.scale_amount_max = 2.6
	var sp := MenuTheme.EL_NATURE.lightened(0.45)
	var sramp := Gradient.new()
	sramp.offsets = PackedFloat32Array([0.0, 0.25, 0.75, 1.0])
	sramp.colors = PackedColorArray([Color(sp, 0.0), Color(sp, 0.45), Color(sp, 0.25), Color(sp, 0.0)])
	_spores.color_ramp = sramp
	add_child(_spores)


func _on_resized() -> void:
	if _particles == null:
		return
	# Emit from a band just below the bottom edge, full width.
	for p in [_particles, _spores]:
		if p != null:
			p.position = Vector2(size.x * 0.5, size.y + 10.0)
			p.emission_rect_extents = Vector2(size.x * 0.55, 20.0)
