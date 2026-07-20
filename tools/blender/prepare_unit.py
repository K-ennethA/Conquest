"""Blender -> Godot unit pipeline.

Takes a raw SCULPT .blend and produces a game-ready .glb, so the artist never has
to think about game-engine concerns (poly budget, UVs, scale, origin, axes) while
sculpting. The source .blend is opened READ-ONLY and never saved over.

Run headless:

    blender --background <input.blend> --factory-startup \
        --python tools/blender/prepare_unit.py -- \
        --output <out.glb> [--target-height 1.8] [--max-footprint 1.9] \
        [--target-faces 10000] [--thorns 0] [--name Foo]

What it does, in order:
  1. Joins every mesh in the file into one object (sculpts often end up split).
  2. OPTIONAL (--thorns N): scatters N procedural spikes over the surface, biased
     toward thin protruding parts. Off by default; runs BEFORE decimation and
     unwrapping so thorns are budgeted and UV'd along with everything else.
  3. Decimates to a target face count -- a sculpt is millions of polys; a tactics
     unit rendered small on an angled camera needs a fraction of that.
  4. Shades smooth, then Smart-UV-unwraps. The unwrap MUST happen after decimation,
     because decimating destroys the old UV layout.
  5. Adds a simple Principled material when the sculpt has none, so it imports as
     something deliberate rather than default grey.
  6. Normalises SCALE against BOTH height and footprint. Every unit occupies one
     2.0-unit cell, so scaling by height alone breaks for sprawling creatures: a
     wide, low flower scaled to 1.8 tall can end up 4+ cells across. The factor is
     therefore min(target_height/height, max_footprint/max(width, depth)), and the
     binding constraint is reported so the artist knows why a model came out small.
  7. Moves the ORIGIN to the feet, centred in X/Y -- units sit at y=0 on a cell
     centre, so a hip-centred origin makes them float or sink.
  8. Applies all transforms and exports .glb with +Y up (Blender is Z-up, Godot is
     Y-up; the exporter converts, and a model facing -Y in Blender ends up facing
     Godot's -Z forward).

Everything is reported so a bad asset is caught here rather than in game.
"""

import bpy
import sys
import math
import random
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
        "max_footprint": 1.9,
        "target_faces": 10000,
        "thorns": 0,
    }
    i = 0
    while i < len(argv):
        key = argv[i].lstrip("-").replace("-", "_")
        if key in opts and i + 1 < len(argv):
            raw = argv[i + 1]
            if key in ("target_height", "max_footprint"):
                opts[key] = float(raw)
            elif key in ("target_faces", "thorns"):
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


def add_thorns(ob, count: int, seed: int = 1337) -> None:
    """Scatter `count` cone spikes over the mesh surface and join them in.

    Opt-in (--thorns). Runs BEFORE decimation/unwrapping so the thorns are part of
    the same poly budget and the same UV layout as the body.

    Placement is biased toward the THIN, PROTRUDING parts -- on a vine creature the
    thorns belong on the tendrils, not smeared over the bulky central body. Two
    cheap heuristics are combined, because either alone misplaces thorns:

      * distance from the centre of mass -- vine TIPS score high, but so does the
        outer rim of a wide flat body;
      * radial distance from the vertical body axis -- catches vines that sweep
        outward, but not one that rears straight up.

    The blend is then cubed, which turns a mild preference into a strong one, and
    faces in the inner half of the range are dropped outright. A minimum-separation
    rejection pass stops thorns clumping on whichever tendril happens to have the
    densest topology (the sculpt is not evenly tessellated, so weight-only sampling
    piles them up). Separation relaxes if the mesh cannot fit the requested count
    rather than looping forever.
    """
    if count <= 0:
        return

    rng = random.Random(seed)
    me = ob.data
    mw = ob.matrix_world
    # Normals need the inverse-transpose in general; identity-safe here either way.
    nm = mw.to_3x3().inverted().transposed()

    if not me.polygons:
        log("WARNING --thorns given but mesh has no faces")
        return

    # Centre of mass, approximated by the vertex average. Good enough as an anchor
    # for "far from the middle" and immune to the bounding box being dragged around
    # by one long tendril.
    com = mathutils.Vector((0.0, 0.0, 0.0))
    for v in me.vertices:
        com += mw @ v.co
    com /= len(me.vertices)

    mn, mx = world_bounds(ob)
    maxdim = max((mx - mn).x, (mx - mn).y, (mx - mn).z)

    # Score every face on the two heuristics, normalised independently so neither
    # dominates purely because the model is wider than it is tall.
    faces = []
    for p in me.polygons:
        c = mw @ p.center
        off = c - com
        faces.append((p.index, c, (nm @ p.normal).normalized(), off.length,
                      math.hypot(off.x, off.y)))

    d_max = max(f[3] for f in faces) or 1.0
    r_max = max(f[4] for f in faces) or 1.0

    scored = []
    for idx, c, n, d, r in faces:
        s = 0.5 * (d / d_max) + 0.5 * (r / r_max)
        scored.append((s, c, n))

    # Drop the inner half outright: the central body should stay smooth.
    s_hi = max(s for s, _, _ in scored)
    cutoff = s_hi * 0.5
    pool = [(s, c, n) for s, c, n in scored if s >= cutoff]
    if len(pool) < count:
        pool = scored
    # Squared, not cubed: cubing pulled almost everything onto the vine TIPS and
    # left the mid-tendril bare. Squared still favours the extremities but spreads
    # thorns along the whole length of each vine.
    weights = [s ** 2 for s, _, _ in pool]

    # Weighted sampling with a minimum-separation rejection test.
    chosen = []
    min_sep = maxdim * 0.05
    attempts = 0
    max_attempts = count * 400
    while len(chosen) < count and attempts < max_attempts:
        attempts += 1
        s, c, n = rng.choices(pool, weights=weights, k=1)[0]
        if all((c - pc).length >= min_sep for pc, _ in chosen):
            chosen.append((c, n))
        elif attempts % (count * 40) == 0:
            min_sep *= 0.7  # mesh is too cramped for the requested count; relax
    if len(chosen) < count:
        log("WARNING placed only %d of %d thorns (mesh too small to separate them)" % (
            len(chosen), count))

    # Thorn scale: ~3-6% of the model's largest dimension, pre-rescale, so the
    # silhouette reads as spiky without the spikes becoming the silhouette.
    base_len = maxdim * 0.038
    spikes = []
    for c, n in chosen:
        length = base_len * rng.uniform(0.75, 1.35)
        # Narrow cones. A wider base looked like a mushroom cap where a vine was
        # thinner than the thorn, and fat cones lose their point to decimation.
        radius = length * rng.uniform(0.20, 0.30)
        # Point +Z (the cone's own axis) along the face normal, then roll randomly
        # so the low-poly cones do not all share a silhouette.
        quat = n.to_track_quat("Z", "Y")
        quat = quat @ mathutils.Quaternion((0.0, 0.0, 1.0), rng.uniform(0, math.tau))
        # Slight tilt keeps them from looking machine-stamped.
        quat = quat @ mathutils.Quaternion(
            mathutils.Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.0)).normalized(),
            rng.uniform(0.0, 0.30))
        # Sink the base under the surface so no gap shows at the join.
        loc = c + (quat @ mathutils.Vector((0.0, 0.0, 1.0))) * (length * 0.5 - length * 0.25)
        bpy.ops.mesh.primitive_cone_add(
            vertices=6, radius1=radius, radius2=0.0, depth=length,
            location=loc, rotation=quat.to_euler())
        spikes.append(bpy.context.view_layer.objects.active)

    if not spikes:
        return

    deselect_all()
    for s in spikes:
        s.select_set(True)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.join()
    log("thorns: %d spikes, len~%.3f (%.1f%% of maxdim %.2f), joined -> %d faces" % (
        len(spikes), base_len, 100.0 * base_len / maxdim, maxdim, len(ob.data.polygons)))


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

    log("source faces=%d" % len(ob.data.polygons))

    # 2. Optional procedural thorns, BEFORE decimation and unwrapping.
    if int(opts["thorns"]) > 0:
        select_only(ob)
        add_thorns(ob, int(opts["thorns"]))
        ob = bpy.context.view_layer.objects.active

    faces_before = len(ob.data.polygons)

    # 3. Decimate to the poly budget.
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

    # 4. Smooth shading + a fresh UV unwrap (the old layout dies with decimation).
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

    # 5. Give it a material if the sculpt had none.
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

    # 6. Normalise scale against BOTH height and footprint (Blender is Z-up, so
    #    height is Z and the footprint is the X/Y extent).
    #
    #    Height alone is wrong for anything that sprawls: a 12.4 x 8.8 x 4.98 flower
    #    scaled to 1.8 tall comes out 4.5 metres wide -- more than two cells -- and
    #    every unit occupies exactly ONE 2.0-unit cell. Taking the smaller of the two
    #    factors means the model always fits, and whichever constraint bound it is
    #    reported so a model that comes out unexpectedly short is self-explaining.
    mn, mx = world_bounds(ob)
    size = mx - mn
    src_height = size.z
    src_footprint = max(size.x, size.y)
    if src_height <= 0.0 or src_footprint <= 0.0:
        log("ERROR degenerate bounds w=%.4f d=%.4f h=%.4f" % (size.x, size.y, size.z))
        return
    height_factor = float(opts["target_height"]) / src_height
    footprint_factor = float(opts["max_footprint"]) / src_footprint
    factor = min(height_factor, footprint_factor)
    bound_by = "height" if height_factor <= footprint_factor else "footprint"
    # MULTIPLY into the object's existing scale, never overwrite it. A sculpt may
    # carry an unapplied, NON-UNIFORM scale (the ancient tree ships at
    # 2.509 x 2.238 x 5.325), and the measured bounds above already include it.
    # Assigning (factor, factor, factor) would throw that authored scale away, so
    # the model would come out both the wrong SIZE and the wrong PROPORTIONS --
    # silently, since it still exports and still fits the cell. Harmless no-op for
    # a sculpt already at scale 1.
    ob.scale = mathutils.Vector((
        ob.scale.x * factor,
        ob.scale.y * factor,
        ob.scale.z * factor))
    bpy.context.view_layer.update()
    log("scale candidates: height %.5f (%.3f -> %.3f), footprint %.5f (%.3f -> %.3f)" % (
        height_factor, src_height, float(opts["target_height"]),
        footprint_factor, src_footprint, float(opts["max_footprint"])))
    log("BOUND BY %s -- scaled by %.5f" % (bound_by.upper(), factor))

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

    # 8. Bake transforms so the exported mesh needs no runtime correction.
    select_only(ob)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    mn, mx = world_bounds(ob)
    size = mx - mn
    log("final size w=%.3f d=%.3f h=%.3f" % (size.x, size.y, size.z))
    log("final origin_at_feet_z=%.4f centred_x=%.4f centred_y=%.4f" % (mn.z, (mn.x + mx.x) / 2.0, (mn.y + mx.y) / 2.0))
    log("final faces=%d verts=%d uv_layers=%d materials=%d" % (
        len(ob.data.polygons), len(ob.data.vertices), len(ob.data.uv_layers), len(ob.data.materials)))

    # Kept as a backstop. Now that scale is clamped by --max-footprint this should
    # never fire; if it does, something upstream is wrong (a stray object dragging
    # the bounds out, or --max-footprint raised above the cell size).
    CELL = 2.0
    if size.x > CELL or size.y > CELL:
        log("NOTE footprint %.2f x %.2f exceeds one %.1f cell -- consider a multi-cell footprint" % (
            size.x, size.y, CELL))

    # 9. Export. +Y up converts Blender's Z-up to Godot's Y-up; a model facing -Y
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
