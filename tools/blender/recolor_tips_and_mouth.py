"""Recolor pass: black body+crown, scorched roots, flame-tipped spikes, red mouth.
Runs on monster_rigged.blend. Renders front + 3/4 for verification.
Tunables via argv: --tip-frac (radial cutoff, default 0.74), --mouth-z0/z1 --mouth-halfw
"""
import bpy, sys, os, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def farg(name, default):
    return float(argv[argv.index(name) + 1]) if name in argv else default
render_dir = argv[argv.index("--renders") + 1] if "--renders" in argv else "."
TIP_FRAC = farg("--tip-frac", 0.74)
MOUTH_Z0 = farg("--mouth-z0", 0.635)
MOUTH_Z1 = farg("--mouth-z1", 0.715)
MOUTH_HW = farg("--mouth-halfw", 0.085)

mesh_obj = bpy.data.objects.get("Monster")
me = mesh_obj.data
xs = [mesh_obj.matrix_world @ v.co for v in me.vertices]
H = max(v.z for v in xs)
mnx, mxx = min(v.x for v in xs), max(v.x for v in xs)
mny, mxy = min(v.y for v in xs), max(v.y for v in xs)
W = mxx - mnx
cx, cy = (mnx + mxx) / 2, (mny + mxy) / 2

# --- materials: reuse existing 3, add mouth ----------------------------------
def ensure_mat(name, rgb, rough=0.9, emit=None, strength=0.0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    return m

mat_body  = ensure_mat("summoner_body",  (0.022, 0.019, 0.024), rough=0.85)
mat_roots = ensure_mat("summoner_roots", (0.045, 0.014, 0.016), rough=0.92)
mat_flame = ensure_mat("summoner_flame", (0.50, 0.05, 0.015), emit=(0.85, 0.10, 0.01), strength=0.7)
mat_mouth = ensure_mat("summoner_mouth", (0.48, 0.020, 0.020), rough=0.6, emit=(0.55, 0.02, 0.01), strength=0.35)

# slots: 0 body, 1 roots, 2 flame, 3 mouth
while len(me.materials) < 4:
    me.materials.append(None)
me.materials[0] = mat_body
me.materials[1] = mat_roots
me.materials[2] = mat_flame
me.materials[3] = mat_mouth

# --- face centers -------------------------------------------------------------
centers = []
for p in me.polygons:
    c = mathutils.Vector((0, 0, 0))
    for vi in p.vertices:
        c += me.vertices[vi].co
    centers.append(c / len(p.vertices))

# --- band-relative radial extremes = spike tips -------------------------------
BANDS = 26
band_max = [0.0] * BANDS
band_of = []
radial = []
for c in centers:
    b = min(BANDS - 1, max(0, int((c.z / H) * BANDS)))
    r = math.hypot(c.x - cx, c.y - cy)
    band_of.append(b)
    radial.append(r)
    band_max[b] = max(band_max[b], r)

skirt_top = H * 0.30
crown_peak = H * 0.90
mouth_faces = 0
tip_faces = 0
# front-most y within the mouth window (mouth is a recess -- use percentile)
mouth_candidates = [i for i, c in enumerate(centers)
                    if MOUTH_Z0 * H <= c.z <= MOUTH_Z1 * H and abs(c.x - cx) <= MOUTH_HW * W and c.y < cy]
mouth_ys = sorted(centers[i].y for i in mouth_candidates)
y_cut = mouth_ys[max(0, int(len(mouth_ys) * 0.35))] if mouth_ys else -1e9

for i, p in enumerate(me.polygons):
    c = centers[i]
    # default by zone
    p.material_index = 1 if c.z < skirt_top else 0
    # spike tips: outer radial fraction of their band (bands with real spread only)
    if band_max[band_of[i]] > W * 0.16 and radial[i] > band_max[band_of[i]] * TIP_FRAC:
        p.material_index = 2
        tip_faces += 1
    # crown apex always burns
    if c.z > crown_peak:
        p.material_index = 2
    # mouth: central front recess window (front 35% of the window's depth)
    if i in ():
        pass
if mouth_candidates:
    msel = set(i for i in mouth_candidates if centers[i].y <= y_cut)
    for i in msel:
        me.polygons[i].material_index = 3
    mouth_faces = len(msel)

print(f"PAINT: tips={tip_faces} mouth={mouth_faces} total={len(me.polygons)}")
me.update()
bpy.ops.wm.save_mainfile()

# --- renders ------------------------------------------------------------------
R = math.radians
scene = bpy.context.scene
cam = bpy.data.objects.new("RecolorCam", bpy.data.cameras.new("RecolorCam"))
scene.collection.objects.link(cam)
scene.camera = cam
sun = bpy.data.objects.new("SunR", bpy.data.lights.new("SunR", type="SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (R(55), 0, R(35))
scene.collection.objects.link(sun)
fill = bpy.data.objects.new("FillR", bpy.data.lights.new("FillR", type="SUN"))
fill.data.energy = 1.2
fill.rotation_euler = (R(60), 0, R(210))
scene.collection.objects.link(fill)
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 768
scene.render.resolution_y = 768
if scene.world is None:
    scene.world = bpy.data.worlds.new("W")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.13, 0.13, 0.15, 1.0)

center = mathutils.Vector((cx, cy, H * 0.5))
dist = H * 1.9
def shoot(loc, out_name):
    cam.location = loc
    d = center - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(render_dir, out_name)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {out_name}")

shoot((center.x, center.y - dist, center.z + H * 0.18), "recolor_front.png")
shoot((center.x + dist * 0.65, center.y - dist * 0.75, center.z + H * 0.35), "recolor_three_quarter.png")
bpy.ops.wm.save_mainfile()
print("RECOLOR DONE")
