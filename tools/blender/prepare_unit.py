"""Blender -> Godot unit pipeline.

Takes a raw SCULPT .blend and produces a game-ready .glb, so the artist never has
to think about game-engine concerns (poly budget, UVs, scale, origin, axes) while
sculpting. The source .blend is opened READ-ONLY and never saved over.

Run headless:

    blender --background <input.blend> --factory-startup \
        --python tools/blender/prepare_unit.py -- \
        --output <out.glb> [--target-height 1.8] [--target-faces 10000] [--name Foo]

What it does, in order:
  1. Joins every mesh in the file into one object (sculpts often end up split).
  2. Decimates to a target face count -- a sculpt is millions of polys; a tactics
     unit rendered small on an angled camera needs a fraction of that.
  3. Shades smooth, then Smart-UV-unwraps. The unwrap MUST happen after decimation,
     because decimating destroys the old UV layout.
  4. Adds a simple Principled material when the sculpt has none, so it imports as
     something deliberate rather than default grey.
  5. Normalises SCALE by height: the board's cells are 2.0 world units, so a unit
     is authored to a real height in metres regardless of the sculpt's size.
  6. Moves the ORIGIN to the feet, centred in X/Y -- units sit at y=0 on a cell
     centre, so a hip-centred origin makes them float or sink.
  7. Applies all transforms and exports .glb with +Y up (Blender is Z-up, Godot is
     Y-up; the exporter converts, and a model facing -Y in Blender ends up facing
     Godot's -Z forward).

Everything is reported so a bad asset is caught here rather than in game.
"""

import bpy
import sys
import mathutils


def parse_args() -> dict:
    """Read args after the '--' separator Blender uses to hand off script args."""
    argv = sys.argv
    if "--" not in argv:
        return {}
    argv = argv[argv.index("--") + 1:]
    opts = {
        "output": "",
        "name": "unit",
        "target_height": 1.8,
        "target_faces": 10000,
    }
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-").replace("-", "_")
        if key in opts and i + 1 < len(argv):
            raw = argv[i + 1]
            if key in ("target_height",):
                opts[key] = float(raw)
            elif key in ("target_faces",):
                opts[key] = int(raw)
            else:
                opts[key] = raw
            i += 2
        else:
            i += 1
    return opts


def log(msg: str) -> None:
    print("PIPELINE " + msg)


def ensure_object_mode() -> None:
    """Force OBJECT mode.

    A sculpt is usually SAVED in Sculpt mode, and in --background almost every
    bpy.ops call then fails with "context is incorrect". Guarded because there may
    be no active object at all yet.
    """
    ob = bpy.context.view_layer.objects.active
    if ob is None:
        for cand in bpy.context.view_layer.objects:
            bpy.context.view_layer.objects.active = cand
            ob = cand
            break
    if ob is not None and ob.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")


def deselect_all() -> None:
    """Deselect without bpy.ops -- the operator needs a context that background
    mode does not reliably provide."""
    for o in bpy.context.view_layer.objects:
        o.select_set(False)


def select_only(ob) -> None:
    deselect_all()
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob


def world_bounds(ob):
    """World-space (min, max) corners of an object's bounding box."""
    corners = [ob.matrix_world @ mathutils.Vector(c) for c in ob.bound_box]
    mn = mathutils.Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    mx = mathutils.Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    return mn, mx


def main() -> None:
    opts = parse_args()
    if not opts.get("output"):
        log("ERROR no --output given")
        return

    # A sculpt is typically saved in Sculpt mode; leave it before touching anything.
    ensure_object_mode()

    # NOTE: the file's camera/light are deliberately left alone. Removing them
    # invalidated object references still held by the view layer (which then broke
    # selection); the export uses use_selection=True, so non-mesh objects can never
    # reach the .glb anyway.
    meshes = [ob for ob in bpy.context.view_layer.objects if ob is not None and ob.type == "MESH"]
    if not meshes:
        log("ERROR no mesh objects found")
        return

    # 1. Join into a single object.
    deselect_all()
    for ob in meshes:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
        log("joined %d meshes" % len(meshes))
    ob = bpy.context.view_layer.objects.active
    ob.name = opts["name"]
    ob.data.name = opts["name"] + "_mesh"

    faces_before = len(ob.data.polygons)
    log("source faces=%d" % faces_before)

    # 2. Decimate to the poly budget.
    target_faces = int(opts["target_faces"])
    if faces_before > target_faces:
        select_only(ob)
        mod = ob.modifiers.new(name="Decimate", type="DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = float(target_faces) / float(faces_before)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        log("decimated %d -> %d faces (ratio %.4f)" % (faces_before, len(ob.data.polygons), mod.ratio))
    else:
        log("no decimation needed (under budget)")

    # 3. Smooth shading + a fresh UV unwrap (the old layout dies with decimation).
    select_only(ob)
    bpy.ops.object.shade_smooth()
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    try:
        bpy.ops.uv.smart_project(angle_limit=1.15192, island_margin=0.02)
        log("smart UV unwrap done")
    except Exception as exc:  # noqa: BLE001 - report and continue, an un-UV'd model still imports
        log("WARNING uv unwrap failed: %s" % exc)
    bpy.ops.object.mode_set(mode="OBJECT")

    # 4. Give it a material if the sculpt had none.
    if not ob.data.materials:
        mat = bpy.data.materials.new(name=opts["name"] + "_mat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf:
            bsdf.inputs["Base Color"].default_value = (0.34, 0.28, 0.20, 1.0)  # bark
            if "Roughness" in bsdf.inputs:
                bsdf.inputs["Roughness"].default_value = 0.85
        ob.data.materials.append(mat)
        log("added default material '%s'" % mat.name)

    # 5. Normalise scale by HEIGHT (Blender is Z-up, so height is Z).
    mn, mx = world_bounds(ob)
    size = mx - mn
    src_height = size.z
    if src_height <= 0.0:
        log("ERROR degenerate height")
        return
    factor = float(opts["target_height"]) / src_height
    ob.scale = (factor, factor, factor)
    bpy.context.view_layer.update()
    log("scaled by %.5f (height %.3f -> %.3f)" % (factor, src_height, float(opts["target_height"])))

    # 6. Origin to the feet, centred in X/Y.
    #    Done with the 3D cursor + origin_set rather than shifting vertices by hand:
    #    the object still carries a scale here, so a hand-rolled local-space offset
    #    silently lands in the wrong place (it put the origin a full unit under the
    #    feet). origin_set does the transform maths correctly.
    mn, mx = world_bounds(ob)
    ctr = (mn + mx) / 2.0
    feet_centre = mathutils.Vector((ctr.x, ctr.y, mn.z))
    select_only(ob)
    bpy.context.scene.cursor.location = feet_centre
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    ob.location = (0.0, 0.0, 0.0)
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()

    # 7. Bake transforms so the exported mesh needs no runtime correction.
    select_only(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = world_bounds(ob)
    size = mx - mn
    log("final size w=%.3f d=%.3f h=%.3f" % (size.x, size.y, size.z))
    log("final origin_at_feet_z=%.4f centred_x=%.4f centred_y=%.4f" % (mn.z, (mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0))
    log("final faces=%d verts=%d uv_layers=%d materials=%d" % (
        len(ob.data.polygons), len(ob.data.vertices), len(ob.data.uv_layers), len(ob.data.materials)))

    # Warn when the model overhangs a single 2.0-unit cell, so the author can decide
    # between rescaling and giving the character a multi-cell footprint.
    CELL = 2.0
    if size.x > CELL or size.y > CELL:
        log("NOTE footprint %.2f x %.2f exceeds one %.1f cell -- consider a multi-cell footprint" % (
            size.x, size.y, CELL))

    # 8. Export. +Y up converts Blender's Z-up to Godot's Y-up; a model facing -Y
    #    here therefore faces Godot's -Z (forward).
    select_only(ob)
    bpy.ops.export_scene.gltf(
        filepath=opts["output"],
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
    )
    log("exported %s" % opts["output"])


main()
