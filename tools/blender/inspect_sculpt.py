"""Headless Blender: inspect a sculpt + render turntable views.
Usage: blender --background <file.blend> --python inspect_monster.py -- --out <dir>
"""
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_dir = argv[argv.index("--out") + 1] if "--out" in argv else "."
os.makedirs(out_dir, exist_ok=True)

print("=== SCENE INVENTORY ===")
meshes = []
for ob in bpy.data.objects:
    print(f"OBJ: {ob.name!r} type={ob.type} visible={not ob.hide_render} "
          f"loc={tuple(round(v, 3) for v in ob.location)} scale={tuple(round(v, 3) for v in ob.scale)}")
    if ob.type == "MESH":
        meshes.append(ob)
        me = ob.data
        print(f"     verts={len(me.vertices)} faces={len(me.polygons)} "
              f"materials={[m.name if m else None for m in me.materials]}")
        dims = ob.dimensions
        print(f"     dimensions={tuple(round(v, 3) for v in dims)}")
        # Loose-part estimate via vertex islands would be slow on sculpt meshes;
        # report modifier stack instead (remesh/multires matter for rigging).
        for mod in ob.modifiers:
            print(f"     modifier: {mod.type} {mod.name!r}")
    if ob.type == "ARMATURE":
        print(f"     bones={[b.name for b in ob.data.bones]}")

print(f"TOTAL mesh objects: {len(meshes)}")
print(f"MATERIALS in file: {[m.name for m in bpy.data.materials]}")
print(f"ACTIONS in file: {[a.name for a in bpy.data.actions]}")

if not meshes:
    print("NO MESHES - nothing to render")
    sys.exit(0)

# --- frame everything ---------------------------------------------------------
min_c = [1e9] * 3
max_c = [-1e9] * 3
for ob in meshes:
    for corner in ob.bound_box:
        world = ob.matrix_world @ bpy.mathutils_Vector(corner) if False else None
    # matrix_world applied properly:
    import mathutils
    for corner in ob.bound_box:
        w = ob.matrix_world @ mathutils.Vector(corner)
        for i in range(3):
            min_c[i] = min(min_c[i], w[i])
            max_c[i] = max(max_c[i], w[i])
center = [(min_c[i] + max_c[i]) / 2 for i in range(3)]
size = max(max_c[i] - min_c[i] for i in range(3))
print(f"WORLD BOUNDS: min={[round(v,2) for v in min_c]} max={[round(v,2) for v in max_c]} size={round(size,2)}")

# --- camera + light rig -------------------------------------------------------
import mathutils
scene = bpy.context.scene
cam_data = bpy.data.cameras.new("TurnCam")
cam = bpy.data.objects.new("TurnCam", cam_data)
scene.collection.objects.link(cam)
scene.camera = cam

sun_data = bpy.data.lights.new("Sun", type="SUN")
sun_data.energy = 3.0
sun = bpy.data.objects.new("Sun", sun_data)
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)

fill_data = bpy.data.lights.new("Fill", type="SUN")
fill_data.energy = 1.0
fill = bpy.data.objects.new("Fill", fill_data)
fill.rotation_euler = (math.radians(60), 0, math.radians(200))
scene.collection.objects.link(fill)

scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 768
scene.render.resolution_y = 768
scene.render.film_transparent = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("W")
scene.world.use_nodes = True
bg = scene.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.12, 0.12, 0.14, 1.0)

dist = size * 2.2
views = {
    "front": (0, -dist, size * 0.35),
    "three_quarter": (dist * 0.75, -dist * 0.75, size * 0.5),
    "side": (dist, 0, size * 0.35),
    "back": (0, dist, size * 0.35),
    "top": (0.001, -0.001, dist * 1.2),
}
for name, offset in views.items():
    cam.location = (center[0] + offset[0], center[1] + offset[1], center[2] + offset[2])
    direction = mathutils.Vector(center) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(out_dir, f"monster_{name}.png")
    bpy.ops.render.render(write_still=True)
    print(f"RENDERED {name} -> {scene.render.filepath}")

print("=== DONE ===")
