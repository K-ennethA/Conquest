"""Headless Blender: prep + auto-rig + color + starter animations for the 'monster' sculpt.

Skirted-totem archetype (rooted wraith, no legs):
  root -> spine -> chest -> head -> crown
  chest -> arm.L/R -> blade.L/R
  root  -> skirt.F/B/L/R (base sway)

Clips authored (names the game's UnitAnimator fuzzy-matches): idle, walk, attack, hit, death.
Saves a NEW file (never overwrites the sculpt) + renders previews.

Usage: blender --background monster.blend --factory-startup --python rig_monster.py -- \
         --save <out.blend> --renders <dir>
"""
import bpy, sys, os, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
save_path = arg("--save", "monster_rigged.blend")
render_dir = arg("--renders", ".")
os.makedirs(render_dir, exist_ok=True)

FPS = 24

# --- 1. find the sculpt -------------------------------------------------------
mesh_obj = None
for ob in bpy.data.objects:
    if ob.type == "MESH":
        mesh_obj = ob
        break
assert mesh_obj, "no mesh in file"
mesh_obj.name = "Monster"
bpy.context.view_layer.objects.active = mesh_obj
for ob in bpy.data.objects:
    ob.select_set(ob is mesh_obj)

# --- 2. cleanup: remesh fine (keep fins) then decimate ------------------------
dims = mesh_obj.dimensions
height = dims.z
vox = max(height / 140.0, 0.02)          # fine enough to keep thin flares
rm = mesh_obj.modifiers.new("Remesh", "REMESH")
rm.mode = "VOXEL"
rm.voxel_size = vox
bpy.ops.object.modifier_apply(modifier=rm.name)
print(f"AFTER REMESH: faces={len(mesh_obj.data.polygons)} (voxel={vox:.3f})")

dec = mesh_obj.modifiers.new("Decimate", "DECIMATE")
target_faces = 9000
dec.ratio = min(1.0, target_faces / max(1, len(mesh_obj.data.polygons)))
bpy.ops.object.modifier_apply(modifier=dec.name)
print(f"AFTER DECIMATE: faces={len(mesh_obj.data.polygons)}")

# flat shading = the house style
for p in mesh_obj.data.polygons:
    p.use_smooth = False

# --- 3. floor-snap + apply transforms (manual matrix math -- headless-proof) --
mesh_obj.data.transform(mesh_obj.matrix_world)
mesh_obj.matrix_world = mathutils.Matrix.Identity(4)
min_z = min(v.co.z for v in mesh_obj.data.vertices)
mesh_obj.data.transform(mathutils.Matrix.Translation((0, 0, -min_z)))
mesh_obj.data.update()

# world bounds after cleanup
def bounds():
    xs = [(mesh_obj.matrix_world @ v.co) for v in mesh_obj.data.vertices]
    mn = mathutils.Vector((min(v.x for v in xs), min(v.y for v in xs), min(v.z for v in xs)))
    mx = mathutils.Vector((max(v.x for v in xs), max(v.y for v in xs), max(v.z for v in xs)))
    return mn, mx
mn, mx = bounds()
H = mx.z - mn.z
W = mx.x - mn.x
cx = (mn.x + mx.x) / 2
cy = (mn.y + mx.y) / 2
print(f"CLEAN BOUNDS: H={H:.2f} W={W:.2f} center=({cx:.2f},{cy:.2f})")

# --- 4. materials: dark-wraith palette by height bands ------------------------
def flat_mat(name, rgb, emit=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = 1.2
    return m

# Aku-style monster-summoner: jet black body, black-maroon roots, burning crimson
# crown (slight emission so the crest smolders even in shadow).
mat_body  = flat_mat("summoner_body",  (0.045, 0.040, 0.048))
mat_roots = flat_mat("summoner_roots", (0.085, 0.030, 0.035))
mat_crown = flat_mat("summoner_flame", (0.62, 0.09, 0.04), emit=(0.90, 0.18, 0.03))
me = mesh_obj.data
me.materials.append(mat_body)   # slot 0
me.materials.append(mat_roots)  # slot 1
me.materials.append(mat_crown)  # slot 2
skirt_top = mn.z + H * 0.30
crown_bot = mn.z + H * 0.72
for p in me.polygons:
    z = sum(me.vertices[v].co.z for v in p.vertices) / len(p.vertices)
    p.material_index = 1 if z < skirt_top else (2 if z > crown_bot else 0)

# --- 5. skeleton --------------------------------------------------------------
arm_data = bpy.data.armatures.new("MonsterRig")
rig = bpy.data.objects.new("MonsterRig", arm_data)
bpy.context.scene.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")

def bone(name, head, tail, parent=None, connect=False):
    b = arm_data.edit_bones.new(name)
    b.head = head
    b.tail = tail
    if parent:
        b.parent = arm_data.edit_bones[parent]
        b.use_connect = connect
    return b

z = lambda f: mn.z + H * f
bone("root",  (cx, cy, z(0.06)), (cx, cy, z(0.30)))
bone("spine", (cx, cy, z(0.30)), (cx, cy, z(0.52)), "root", True)
bone("chest", (cx, cy, z(0.52)), (cx, cy, z(0.68)), "spine", True)
bone("head",  (cx, cy, z(0.68)), (cx, cy, z(0.82)), "chest", True)
bone("crown", (cx, cy, z(0.82)), (cx, cy, z(0.99)), "head", True)
aw = W * 0.5
bone("arm.L",   (cx + W*0.10, cy, z(0.60)), (cx + aw*0.55, cy, z(0.63)), "chest")
bone("blade.L", (cx + aw*0.55, cy, z(0.63)), (cx + aw*0.98, cy, z(0.58)), "arm.L", True)
bone("arm.R",   (cx - W*0.10, cy, z(0.60)), (cx - aw*0.55, cy, z(0.63)), "chest")
bone("blade.R", (cx - aw*0.55, cy, z(0.63)), (cx - aw*0.98, cy, z(0.58)), "arm.R", True)
sk = W * 0.38
for name, (dx, dy) in {"skirt.F": (0, -1), "skirt.B": (0, 1), "skirt.L": (1, 0), "skirt.R": (-1, 0)}.items():
    bone(name, (cx + dx*W*0.08, cy + dy*W*0.08, z(0.16)),
               (cx + dx*sk,      cy + dy*sk,      z(0.05)), "root")

bpy.ops.object.mode_set(mode="OBJECT")

# --- 6. bind with automatic weights ------------------------------------------
for ob in bpy.data.objects:
    ob.select_set(False)
mesh_obj.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_AUTO")
print("BOUND with automatic weights; groups:", [g.name for g in mesh_obj.vertex_groups])

# --- 7. animations ------------------------------------------------------------
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="POSE")
pose = rig.pose.bones
scene = bpy.context.scene
scene.render.fps = FPS

def reset_pose():
    for pb in pose:
        pb.location = (0, 0, 0)
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0, 0, 0)
        pb.scale = (1, 1, 1)

def key_all(frame, bones=None):
    for pb in pose:
        if bones and pb.name not in bones:
            continue
        pb.keyframe_insert("location", frame=frame)
        pb.keyframe_insert("rotation_euler", frame=frame)

def new_action(name, end):
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = act
    scene.frame_start = 1
    scene.frame_end = end
    reset_pose()
    return act

def stash(act):
    track = rig.animation_data.nla_tracks.new()
    track.name = act.name
    track.strips.new(act.name, 1, act)
    rig.animation_data.action = None

R = math.radians

# IDLE 48f loop: root bob, crown sway, skirt breathe, arms drift
act = new_action("idle", 48)
for f, boblift, sway in ((1, 0.0, 0.0), (13, H*0.010, 3.0), (25, 0.0, 0.0), (37, H*0.010, -3.0), (48, 0.0, 0.0)):
    pose["root"].location = (0, 0, boblift)
    pose["crown"].rotation_euler = (R(sway * 0.8), 0, R(sway))
    pose["head"].rotation_euler = (0, 0, R(sway * 0.5))
    pose["arm.L"].rotation_euler = (0, R(sway * 0.8), 0)
    pose["arm.R"].rotation_euler = (0, R(-sway * 0.8), 0)
    for s in ("skirt.F", "skirt.B", "skirt.L", "skirt.R"):
        pose[s].rotation_euler = (R(abs(sway) * 0.7), 0, 0)
    key_all(f)
stash(act)

# WALK 20f loop: glide — lean forward, skirt ripple alternating, bob x2
act = new_action("walk", 20)
for f, lift, ripple in ((1, 0.0, 4.0), (6, H*0.012, -4.0), (11, 0.0, 4.0), (16, H*0.012, -4.0), (20, 0.0, 4.0)):
    pose["spine"].rotation_euler = (R(-6), 0, 0)          # forward lean (into -Y facing)
    pose["root"].location = (0, 0, lift)
    pose["skirt.F"].rotation_euler = (R(-8 + ripple), 0, 0)
    pose["skirt.B"].rotation_euler = (R(8 - ripple), 0, 0)
    pose["skirt.L"].rotation_euler = (R(ripple), 0, 0)
    pose["skirt.R"].rotation_euler = (R(-ripple), 0, 0)
    pose["arm.L"].rotation_euler = (R(ripple * 0.6), 0, 0)
    pose["arm.R"].rotation_euler = (R(-ripple * 0.6), 0, 0)
    key_all(f)
stash(act)

# ATTACK 16f: rear back (1-5), double-blade slash fast (6-8), recover (9-16)
act = new_action("attack", 16)
key_all(1)
pose["spine"].rotation_euler = (R(10), 0, 0)
pose["arm.L"].rotation_euler = (0, R(35), R(20))
pose["arm.R"].rotation_euler = (0, R(-35), R(-20))
pose["blade.L"].rotation_euler = (0, R(25), 0)
pose["blade.R"].rotation_euler = (0, R(-25), 0)
key_all(5)
pose["spine"].rotation_euler = (R(-14), 0, 0)
pose["arm.L"].rotation_euler = (R(-20), R(-50), R(-25))
pose["arm.R"].rotation_euler = (R(-20), R(50), R(25))
pose["blade.L"].rotation_euler = (0, R(-30), 0)
pose["blade.R"].rotation_euler = (0, R(30), 0)
pose["crown"].rotation_euler = (R(-12), 0, 0)
key_all(8)
reset_pose()
key_all(16)
stash(act)

# HIT 10f: sharp recoil + twist, settle
act = new_action("hit", 10)
key_all(1)
pose["spine"].rotation_euler = (R(14), 0, R(8))
pose["head"].rotation_euler = (R(10), 0, R(-6))
pose["root"].location = (0, H*0.02, 0)
key_all(3)
reset_pose()
key_all(10)
stash(act)

# DEATH 26f: rear up, then fold/crumple down into the skirt, held
act = new_action("death", 26)
key_all(1)
pose["spine"].rotation_euler = (R(-12), 0, 0)
pose["crown"].rotation_euler = (R(-15), 0, 0)
key_all(6)
pose["root"].location = (0, 0, -H * 0.22)
pose["spine"].rotation_euler = (R(34), 0, R(10))
pose["chest"].rotation_euler = (R(20), 0, 0)
pose["head"].rotation_euler = (R(28), 0, 0)
pose["crown"].rotation_euler = (R(30), 0, R(15))
pose["arm.L"].rotation_euler = (R(30), R(20), 0)
pose["arm.R"].rotation_euler = (R(30), R(-20), 0)
for s in ("skirt.F", "skirt.B", "skirt.L", "skirt.R"):
    pose[s].rotation_euler = (R(18), 0, 0)
key_all(18)
key_all(26)   # hold
stash(act)

bpy.ops.object.mode_set(mode="OBJECT")
print("ACTIONS:", [a.name for a in bpy.data.actions])

# --- 8. save ------------------------------------------------------------------
bpy.ops.wm.save_as_mainfile(filepath=save_path)
print(f"SAVED {save_path}")

# --- 9. preview renders: bind pose + mid-attack + mid-walk --------------------
scene = bpy.context.scene
cam_data = bpy.data.cameras.new("PrevCam")
cam = bpy.data.objects.new("PrevCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam
sun = bpy.data.objects.new("Sun2", bpy.data.lights.new("Sun2", type="SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (R(55), 0, R(35))
scene.collection.objects.link(sun)
fill = bpy.data.objects.new("Fill2", bpy.data.lights.new("Fill2", type="SUN"))
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
    bg.inputs[0].default_value = (0.12, 0.12, 0.14, 1.0)

center = mathutils.Vector((cx, cy, H * 0.5))
dist = H * 1.9
cam.location = (center.x + dist * 0.65, center.y - dist * 0.75, center.z + H * 0.35)
d = center - cam.location
cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()

def render_pose(action_name, frame, out_name):
    if action_name:
        act = bpy.data.actions.get(action_name)
        rig.animation_data.action = act
        scene.frame_set(frame)
    scene.render.filepath = os.path.join(render_dir, out_name)
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {out_name}")
    if action_name:
        rig.animation_data.action = None

render_pose(None, 1, "rigged_bindpose.png")
render_pose("attack", 8, "rigged_attack_strike.png")
render_pose("walk", 6, "rigged_walk_mid.png")
render_pose("death", 22, "rigged_death.png")
print("=== RIG DONE ===")
