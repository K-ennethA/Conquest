@tool
class_name OrnateStyleBox
extends StyleBox

## The "illuminated grove" frame: Conquest's custom card / button / chip look,
## drawn procedurally so no texture assets are needed.
##
## One StyleBox that renders, in order:
##   drop shadow -> outer glow -> gradient fill -> fine diagonal hatch (paper grain)
##   -> soft inner vignette -> accent stripe (team / element) -> outer border
##   -> inset gold filigree line -> corner ornaments (clasps or leaves)
##   -> top crest (diamond + leaf sprig) -> focus leaf marker.
##
## Shapes: CHAMFER (notched corners -- the default card), TAG (pointed ends --
## chips, primary buttons), BANNER (swallow-tailed ends -- phase banner, title
## ribbons) and SHIELD (heraldic crest -- unit portraits).
##
## It is a real [StyleBox], so it drops into any theme slot ("panel", "normal",
## "focus"...) and every existing PanelContainer / Button gets the frame for free.
## Presets live in [MenuTheme] (card_box, inset_box, pill_box, focus_box, ribbon_box,
## crest_box...) -- screens should use those rather than configuring this directly.
## Property names mirror [StyleBoxFlat] (bg_color, border_color, shadow_*,
## set_border_width_all, set_corner_radius_all) so older call sites keep working.
##
## Cost: drawing only happens when the owning control redraws (the canvas item
## caches the commands), and the heaviest box -- a big card -- is ~150 line
## segments plus a handful of polygons.

enum Shape { CHAMFER, TAG, BANNER, SHIELD }
enum Ornament { NONE, CLASP, LEAF }

const CUT_TL := 1
const CUT_TR := 2
const CUT_BR := 4
const CUT_BL := 8
const CUT_ALL := 15

@export var shape: Shape = Shape.CHAMFER
@export var draw_center: bool = true
## Fill colour at the top (or left, see [member gradient_horizontal]).
@export var bg_color: Color = Color("172043")
## Fill colour at the bottom / right. Alpha 0 = same as [member bg_color].
@export var bg_color_end: Color = Color(0, 0, 0, 0)
@export var gradient_horizontal: bool = false
## Fade the fill out to fully clear at the bottom / right (ribbon washes on rows).
@export var fade_out: bool = false
## Chamfer size (CHAMFER / SHIELD), point depth (TAG) or notch depth (BANNER).
@export var corner: float = 10.0
## Which corners a CHAMFER cuts (CUT_* bitmask).
@export var cut_corners: int = CUT_ALL
@export var border_color: Color = Color("3a4b86")
@export var border_width: float = 1.5
## The inset filigree line (alpha 0 = none).
@export var inner_line_color: Color = Color(0, 0, 0, 0)
@export var inner_inset: float = 5.0
@export var ornament: Ornament = Ornament.NONE
@export var ornament_color: Color = Color("e8b454")
@export var ornament_size: float = 4.0
## Top-centre crest: a gold diamond with a leaf either side, straddling the border.
@export var crest: bool = false
@export var crest_color: Color = Color(0, 0, 0, 0)
## Fine diagonal hatch over the fill ("paper grain"), 0 = off.
@export var hatch_alpha: float = 0.0
@export var hatch_spacing: float = 6.0
## Soft darkening towards the inside of the border, 0 = off.
@export var vignette_alpha: float = 0.0
@export var vignette_width: float = 14.0
## A stripe of colour just inside the border (team / element edge). Alpha 0 = none.
@export var accent_color: Color = Color(0, 0, 0, 0)
@export var accent_side: Side = SIDE_LEFT
@export var accent_width: float = 4.0
## A second stripe on the OPPOSITE side (forecast: attacker left, defender right).
@export var accent_color_2: Color = Color(0, 0, 0, 0)
## 1px highlight just inside the top edge (bevel), 0 = off.
@export var sheen: float = 0.0
@export var shadow_color: Color = Color(0, 0, 0, 0)
@export var shadow_size: float = 0.0
@export var shadow_offset: Vector2 = Vector2.ZERO
## Outer glow (focus rings), alpha 0 = none.
@export var glow_color: Color = Color(0, 0, 0, 0)
@export var glow_size: float = 0.0
## A leaf marker at the left edge (focused command rows), alpha 0 = none.
@export var marker_color: Color = Color(0, 0, 0, 0)
@export var marker_size: float = 7.0
@export var expand_margin: float = 0.0
@export var anti_aliasing: bool = true


# --- StyleBoxFlat-compatible helpers -------------------------------------------------

func set_border_width_all(w: int) -> void:
	border_width = float(w)
	emit_changed()


func set_corner_radius_all(r: int) -> void:
	corner = clampf(float(r), 0.0, 14.0)
	emit_changed()


func set_expand_margin_all(m: float) -> void:
	expand_margin = m
	emit_changed()


## Copy with a different fill / border (handy for hover / selected variants).
func tinted(fill: Color, border: Color) -> OrnateStyleBox:
	var sb := duplicate() as OrnateStyleBox
	sb.bg_color = fill
	sb.bg_color_end = Color(0, 0, 0, 0)
	sb.border_color = border
	return sb


# --- StyleBox virtuals ------------------------------------------------------------------

func _get_draw_rect(rect: Rect2) -> Rect2:
	return rect.grow(expand_margin)


func _draw(ci: RID, rect: Rect2) -> void:
	var r := rect.grow(expand_margin)
	if r.size.x < 2.0 or r.size.y < 2.0:
		return
	var c := _corner_for(r)
	var rs := RenderingServer

	# Shadow: stacked, growing silhouettes = a soft falloff.
	if shadow_size > 0.0 and shadow_color.a > 0.0:
		var steps := 4
		var col := Color(shadow_color.r, shadow_color.g, shadow_color.b, shadow_color.a / float(steps) * 1.3)
		for i in steps:
			var g := shadow_size * float(i + 1) / float(steps) - shadow_size * 0.35
			var pts := _shape(Rect2(r.position + shadow_offset, r.size).grow(g), c + g * 0.4)
			rs.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))

	# Glow: rings outside the edge fading out.
	if glow_size > 0.0 and glow_color.a > 0.0:
		var gsteps := 4
		for i in gsteps:
			var g := glow_size * (float(i) + 0.5) / float(gsteps)
			var a := glow_color.a * pow(1.0 - float(i) / float(gsteps), 1.6)
			_polyline(ci, _shape(r.grow(g), c + g * 0.4),
				Color(glow_color.r, glow_color.g, glow_color.b, a), glow_size / float(gsteps) + 0.6)

	var outer := _shape(r, c)
	if draw_center:
		# Gradient fill (per-vertex colours are exact for a linear gradient).
		var end := bg_color_end if bg_color_end.a > 0.0 else bg_color
		if fade_out:
			end = Color(bg_color, 0.0)
		var cols := PackedColorArray()
		cols.resize(outer.size())
		for i in outer.size():
			var t: float
			if gradient_horizontal:
				t = (outer[i].x - r.position.x) / r.size.x
			else:
				t = (outer[i].y - r.position.y) / r.size.y
			cols[i] = bg_color.lerp(end, clampf(t, 0.0, 1.0))
		rs.canvas_item_add_polygon(ci, outer, cols)

		if hatch_alpha > 0.0:
			_draw_hatch(ci, r, c)

		if vignette_alpha > 0.0:
			var vsteps := 5
			for i in vsteps:
				var inset := border_width + vignette_width * (float(i) + 0.5) / float(vsteps)
				if inset * 2.0 >= minf(r.size.x, r.size.y):
					break
				var a := vignette_alpha * pow(1.0 - float(i) / float(vsteps), 2.0)
				_polyline(ci, _shape(r.grow(-inset), _inset_corner(c, inset)),
					Color(0, 0, 0, a), vignette_width / float(vsteps) + 0.5)

	if accent_color.a > 0.0 and accent_width > 0.0:
		_draw_accent(ci, r, c, accent_side, accent_color)
	if accent_color_2.a > 0.0 and accent_width > 0.0:
		var opposite := {SIDE_LEFT: SIDE_RIGHT, SIDE_RIGHT: SIDE_LEFT, SIDE_TOP: SIDE_BOTTOM,
			SIDE_BOTTOM: SIDE_TOP}
		_draw_accent(ci, r, c, opposite[accent_side], accent_color_2)

	if sheen > 0.0 and shape != Shape.SHIELD:
		var y := r.position.y + border_width + 0.5
		var x0 := r.position.x + (c if shape != Shape.BANNER else 0.0) + 2.0
		var x1 := r.end.x - (c if shape != Shape.BANNER else 0.0) - 2.0
		if x1 > x0:
			rs.canvas_item_add_line(ci, Vector2(x0, y), Vector2(x1, y), Color(1, 1, 1, sheen), 1.0, anti_aliasing)

	if border_width > 0.0 and border_color.a > 0.0:
		_polyline(ci, _shape(r.grow(-border_width * 0.5), _inset_corner(c, border_width * 0.5)),
			border_color, border_width)

	var inner := PackedVector2Array()
	if inner_inset * 2.0 < minf(r.size.x, r.size.y):
		inner = _shape(r.grow(-inner_inset), _inset_corner(c, inner_inset))
	if inner_line_color.a > 0.0 and not inner.is_empty():
		_polyline(ci, inner, inner_line_color, 1.0)

	if ornament != Ornament.NONE and ornament_color.a > 0.0 and shape == Shape.CHAMFER \
			and r.size.y >= ornament_size * 5.0:
		_draw_corner_ornaments(ci, r, c)

	if crest and r.size.x > 60.0:
		_draw_crest(ci, r)

	if marker_color.a > 0.0:
		var m := Vector2(r.position.x + border_width + 5.0, r.position.y + r.size.y * 0.5)
		OrnateStyleBox.draw_leaf(ci, m, Vector2.RIGHT, marker_size * 1.9, marker_size, marker_color)


# --- Geometry -------------------------------------------------------------------------

func _corner_for(r: Rect2) -> float:
	var lim := minf(r.size.x, r.size.y)
	match shape:
		Shape.TAG:
			return minf(corner, r.size.y * 0.5)
		Shape.BANNER:
			return minf(corner, r.size.x * 0.2)
		_:
			return minf(corner, lim * 0.34)


func _inset_corner(c: float, inset: float) -> float:
	match shape:
		Shape.CHAMFER, Shape.SHIELD:
			return maxf(0.0, c - inset * 0.414)
	return c


## Outline of this box's shape inside [param r] (clockwise, screen space).
func _shape(r: Rect2, c: float) -> PackedVector2Array:
	var x0 := r.position.x
	var y0 := r.position.y
	var x1 := r.end.x
	var y1 := r.end.y
	var ym := (y0 + y1) * 0.5
	var p := PackedVector2Array()
	match shape:
		Shape.TAG:
			var d := minf(c, (y1 - y0) * 0.5)
			d = minf(d, (x1 - x0) * 0.3)
			p.append_array([Vector2(x0, ym), Vector2(x0 + d, y0), Vector2(x1 - d, y0),
				Vector2(x1, ym), Vector2(x1 - d, y1), Vector2(x0 + d, y1)])
		Shape.BANNER:
			var n := minf(c, (x1 - x0) * 0.2)
			p.append_array([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1 - n, ym),
				Vector2(x1, y1), Vector2(x0, y1), Vector2(x0 + n, ym)])
		Shape.SHIELD:
			var w := x1 - x0
			var h := y1 - y0
			var xm := (x0 + x1) * 0.5
			var cc := minf(c, w * 0.2)
			var ys := y0 + h * 0.46
			p.append_array([Vector2(x0 + cc, y0), Vector2(x1 - cc, y0), Vector2(x1, y0 + cc),
				Vector2(x1, ys)])
			var seg := 7
			for i in range(1, seg + 1):
				var t := float(i) / float(seg)
				p.append(_quad(Vector2(x1, ys), Vector2(x1, y1 - h * 0.14), Vector2(xm, y1), t))
			for i in range(1, seg + 1):
				var t := float(i) / float(seg)
				p.append(_quad(Vector2(xm, y1), Vector2(x0, y1 - h * 0.14), Vector2(x0, ys), t))
			p.append(Vector2(x0, y0 + cc))
		_:
			if cut_corners & CUT_TL and c > 0.0:
				p.append_array([Vector2(x0, y0 + c), Vector2(x0 + c, y0)])
			else:
				p.append(Vector2(x0, y0))
			if cut_corners & CUT_TR and c > 0.0:
				p.append_array([Vector2(x1 - c, y0), Vector2(x1, y0 + c)])
			else:
				p.append(Vector2(x1, y0))
			if cut_corners & CUT_BR and c > 0.0:
				p.append_array([Vector2(x1, y1 - c), Vector2(x1 - c, y1)])
			else:
				p.append(Vector2(x1, y1))
			if cut_corners & CUT_BL and c > 0.0:
				p.append_array([Vector2(x0 + c, y1), Vector2(x0, y1 - c)])
			else:
				p.append(Vector2(x0, y1))
	return p


static func _quad(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u + b * 2.0 * u * t + c * t * t


func _polyline(ci: RID, pts: PackedVector2Array, col: Color, width: float) -> void:
	if pts.size() < 2:
		return
	var closed := pts.duplicate()
	closed.append(pts[0])
	RenderingServer.canvas_item_add_polyline(ci, closed, PackedColorArray([col]), width, anti_aliasing)


func _draw_hatch(ci: RID, r: Rect2, c: float) -> void:
	var inset := border_width + 1.0
	var clip: PackedVector2Array
	if shape == Shape.BANNER:
		var n := _corner_for(r)
		clip = PackedVector2Array([Vector2(r.position.x + n, r.position.y + inset),
			Vector2(r.end.x - n, r.position.y + inset), Vector2(r.end.x - n, r.end.y - inset),
			Vector2(r.position.x + n, r.end.y - inset)])
	else:
		clip = _shape(r.grow(-inset), _inset_corner(c, inset))
	var step := maxf(hatch_spacing, 3.0)
	var pts := PackedVector2Array()
	var k := r.position.x + r.position.y + step * 0.5
	var k_end := r.end.x + r.end.y
	var y0 := r.position.y - 1.0
	var y1 := r.end.y + 1.0
	while k < k_end:
		var a := Vector2(k - y1, y1)
		var b := Vector2(k - y0, y0)
		var seg := clip_segment(a, b, clip)
		if not seg.is_empty():
			pts.append(seg[0])
			pts.append(seg[1])
		k += step
	if not pts.is_empty():
		RenderingServer.canvas_item_add_multiline(ci, pts, PackedColorArray([Color(1, 0.96, 0.85, hatch_alpha)]), 1.0)


## Cyrus-Beck: clip segment a-b to the convex clockwise polygon [param poly].
## Returns [] when fully outside, else [start, end].
static func clip_segment(a: Vector2, b: Vector2, poly: PackedVector2Array) -> PackedVector2Array:
	var d := b - a
	var t0 := 0.0
	var t1 := 1.0
	var n := poly.size()
	for i in n:
		var p0 := poly[i]
		var e := poly[(i + 1) % n] - p0
		var nrm := Vector2(-e.y, e.x)
		var num := nrm.dot(a - p0)
		var den := nrm.dot(d)
		if absf(den) < 0.000001:
			if num < 0.0:
				return PackedVector2Array()
			continue
		var t := -num / den
		if den > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


func _draw_accent(ci: RID, r: Rect2, c: float, side: int, col: Color) -> void:
	var bw := border_width
	var aw := accent_width
	var q: Rect2
	match side:
		SIDE_TOP:
			q = Rect2(r.position.x + c + 2.0, r.position.y + bw, r.size.x - 2.0 * c - 4.0, aw)
		SIDE_BOTTOM:
			q = Rect2(r.position.x + c + 2.0, r.end.y - bw - aw, r.size.x - 2.0 * c - 4.0, aw)
		SIDE_RIGHT:
			q = Rect2(r.end.x - bw - aw, r.position.y + c + 2.0, aw, r.size.y - 2.0 * c - 4.0)
		_:
			q = Rect2(r.position.x + bw, r.position.y + c + 2.0, aw, r.size.y - 2.0 * c - 4.0)
	if q.size.x <= 0.0 or q.size.y <= 0.0:
		return
	RenderingServer.canvas_item_add_rect(ci, q, col)


func _draw_corner_ornaments(ci: RID, r: Rect2, c: float) -> void:
	var ins := inner_inset if inner_line_color.a > 0.0 else border_width + 3.0
	var ic := _inset_corner(c, ins)
	var ir := r.grow(-ins)
	var s := ornament_size
	var corners := [
		[CUT_TL, ir.position, Vector2(-1, -1)],
		[CUT_TR, Vector2(ir.end.x, ir.position.y), Vector2(1, -1)],
		[CUT_BR, ir.end, Vector2(1, 1)],
		[CUT_BL, Vector2(ir.position.x, ir.end.y), Vector2(-1, 1)],
	]
	var dark := Color(0.04, 0.05, 0.1, 0.9)
	for cn in corners:
		var outward: Vector2 = (cn[2] as Vector2).normalized()
		var corner_pt: Vector2 = cn[1]
		# The ornament sits on the inner line's chamfer (or the square corner).
		var m: Vector2 = corner_pt
		if cut_corners & int(cn[0]) and ic > 0.0:
			m = corner_pt - outward * (ic * 0.7071)
		if ornament == Ornament.LEAF:
			OrnateStyleBox.draw_leaf(ci, m + outward * s * 0.2, -outward, s * 2.6, s * 1.25, ornament_color)
		else:
			var along := Vector2(-outward.y, outward.x)
			var pts := PackedVector2Array([m + along * s * 1.35, m + outward * s * 0.85,
				m - along * s * 1.35, m - outward * s * 0.85])
			RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([ornament_color]))
			RenderingServer.canvas_item_add_circle(ci, m, maxf(0.9, s * 0.28), dark)


func _draw_crest(ci: RID, r: Rect2) -> void:
	var col := crest_color if crest_color.a > 0.0 else ornament_color
	var s := maxf(ornament_size, 3.0) * 1.3
	var m := Vector2(r.position.x + r.size.x * 0.5, r.position.y + border_width * 0.5)
	# Leaf sprig either side, lying along the top edge.
	OrnateStyleBox.draw_leaf(ci, m + Vector2(s * 0.9, 0), Vector2.RIGHT, s * 2.6, s * 1.0, col)
	OrnateStyleBox.draw_leaf(ci, m - Vector2(s * 0.9, 0), Vector2.LEFT, s * 2.6, s * 1.0, col)
	var pts := PackedVector2Array([m + Vector2(0, -s * 1.15), m + Vector2(s * 0.8, 0),
		m + Vector2(0, s * 1.15), m + Vector2(-s * 0.8, 0)])
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))
	var inner := PackedVector2Array([m + Vector2(0, -s * 0.5), m + Vector2(s * 0.35, 0),
		m + Vector2(0, s * 0.5), m + Vector2(-s * 0.35, 0)])
	RenderingServer.canvas_item_add_polygon(ci, inner, PackedColorArray([bg_color.darkened(0.2)]))


# --- Glyph helpers (shared with GroveGlyph / crest controls) ----------------------------

## A leaf (vesica with a vein) from [param base] pointing along [param dir].
static func draw_leaf(ci: RID, base: Vector2, dir: Vector2, length: float, width: float, col: Color) -> void:
	var pts := leaf_points(base, dir, length, width)
	RenderingServer.canvas_item_add_polygon(ci, pts, PackedColorArray([col]))
	if length > 9.0:
		var vein := Color(0, 0, 0, 0.35 * col.a)
		RenderingServer.canvas_item_add_line(ci, base + dir.normalized() * length * 0.12,
			base + dir.normalized() * length * 0.8, vein, 1.0, true)


static func leaf_points(base: Vector2, dir: Vector2, length: float, width: float) -> PackedVector2Array:
	var u := dir.normalized()
	var v := Vector2(-u.y, u.x)
	var pts := PackedVector2Array()
	var n := 7
	for i in range(0, n + 1):
		var t := float(i) / float(n)
		pts.append(base + u * t * length + v * sin(PI * t) * (1.0 - 0.35 * t) * width * 0.5)
	for i in range(n - 1, 0, -1):
		var t := float(i) / float(n)
		pts.append(base + u * t * length - v * sin(PI * t) * (1.0 - 0.35 * t) * width * 0.5)
	return pts
