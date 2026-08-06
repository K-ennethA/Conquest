"""Rig-aware glb export for monster_rigged.blend (prepare_unit.py predates armatures).
Same cell-fit contract as the pipeline: scale = min(target_height/H, max_footprint/max(W,D)),
origin at feet center, +Y up, animations included, flat shading and materials preserved.
"""
import bpy, sys, math, mathutils

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
def arg(name, default):
    return argv[argv.index(name) + 1] if name in argv else default
out = arg("--output", "monster.glb")
target_h = float(arg("--target-height", "1.8"))
max_fp = float(arg("--max-footprint", "1.9"))

mesh_obj = bpy.data.objects["Monster"]
rig = bpy.data.objects["MonsterRig"]

# strip preview cameras/lights so the glb is clean
for ob in list(bpy.data.objects):
    if ob.type in ("CAMERA", "LIGHT"):
        bpy.data.objects.remove(ob, do_unlink=True)

# cell-fit scale on the RIG (mesh is parented to it, so scaling the rig scales both;
# animations are bone-local rotations + root locations, which scale with the object)
xs = [mesh_obj.matrix_world @ v.co for v in mesh_obj.data.vertices]
H = max(v.z for v in xs) - min(v.z for v in xs)
W = max(v.x for v in xs) - min(v.x for v in xs)
D = max(v.y for v in xs) - min(v.y for v in xs)
s_h = target_h / H
s_f = max_fp / max(W, D)
s = min(s_h, s_f)
print(f"scale candidates: height {s_h:.5f} ({H:.3f} -> {target_h}), footprint {s_f:.5f} ({max(W,D):.3f} -> {max_fp})")
print(f"chosen scale {s:.5f} -> final H={H*s:.3f} W={W*s:.3f} D={D*s:.3f}")

rig.scale = (s, s, s)
# feet-center origin: mesh already floor-snapped at z=0 with centered x/y in rig space
cx = (min(v.x for v in xs) + max(v.x for v in xs)) / 2 * s
cy = (min(v.y for v in xs) + max(v.y for v in xs)) / 2 * s
rig.location = (-cx, -cy, 0)

bpy.ops.export_scene.gltf(
    filepath=out,
    export_format="GLB",
    export_yup=True,
    export_apply=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_materials="EXPORT",
    export_skins=True,
)
print(f"EXPORTED {out}")
print("clips:", [a.name for a in bpy.data.actions])
