"""Parametric gift-bow generator: the source of `assets/tail_bow/tail_bow.glb`.

Authoring frame (before the final `orient()`): origin at the knot centre, +X lateral, +Y up
(tails hang toward -Y), +Z out of the bow's face. `orient()` turns that into Blender's +Z-up
frame, so the glTF export lands as +Y up and +Z out for the runtime.

Run it against a live Blender (MCP or the Python console):

    exec(compile(open("tools/tail_bow/build_bow.py").read(), "build_bow.py", "exec"))

It rebuilds the scene objects, writes the six preview renders to /tmp/opencode/bow_*.png and
prints `PART` bounds per piece. Then export with `export_glb()`; set `NO_RENDER = True` before
the exec to skip the renders, or `NO_MAIN = True` to only define the helpers.
"""

import bpy
import bmesh
import math
import os
from mathutils import Vector, Matrix

OUT = "/tmp/opencode"
R_NOMINAL = 0.060

P = {
    "band_w": 0.0260,       # loop ribbon width (radial): hole is the gap left over
    "band_t": 0.0022,       # ribbon thickness
    "fold": 0.22,           # cross-section bulge, share of half width
    "loop_dish": 0.55,      # outer edge tips toward the viewer: the cup
    "loop_edge": 0.35,      # thicker rolled outer edge
    "loop_samples": 46,
    "loop_tilt_deg": 34.0,  # top of the loop leans toward the viewer
    "loop_splay_deg": 10.0, # outer end leans away from the viewer
    "tail_w": 0.0340,       # half width at the knot
    "tail_len": 0.118,
    "tail_notch": 0.032,    # V depth up from the tip
    "tail_notch_w": 0.0230,  # V opening at the tip
    "knot": (0.030, 0.030, 0.026),
    "knot_bevel": 0.010,
    "strap_w": 0.008,
    "strap_t": 0.0016,
    "strap_sink": 0.0045,    # the strap hides inside the fur
}

LOOP_CTRL = [
    Vector((0.014, 0.002)),
    Vector((0.030, 0.027)),
    Vector((0.052, 0.027)),
    Vector((0.061, 0.002)),
    Vector((0.052, -0.022)),
    Vector((0.030, -0.025)),
    Vector((0.014, -0.005)),
]


def catmull(pts, n):
    p = [pts[0]] + list(pts) + [pts[-1]]
    segs = len(pts) - 1
    out = []
    for i in range(n):
        f = (i / (n - 1)) * segs
        k = min(int(f), segs - 1)
        t = f - k
        a, b, c, d = p[k], p[k + 1], p[k + 2], p[k + 3]
        t2, t3 = t * t, t * t * t
        out.append(0.5 * ((2 * b) + (-a + c) * t
                          + (2 * a - 5 * b + 4 * c - d) * t2
                          + (-a + 3 * b - 3 * c + d) * t3))
    return out


def tangents(path):
    out = []
    n = len(path)
    for i in range(n):
        a = path[max(i - 1, 0)]
        b = path[min(i + 1, n - 1)]
        t = b - a
        out.append(t.normalized() if t.length > 1e-9 else Vector((0, 1, 0)))
    return out


def sweep(path, normals, halfwidths, fold, thickness, steps=8, arc=3,
          dish=0.0, edge=0.0):
    """Solid ribbon: rounded rectangular section swept along `path`.

    `fold` domes the middle of the band, `dish` tilts it across the width
    (outer edge toward +normal), `edge` thickens the outer edge like a rolled fold.
    """
    tans = tangents(path)
    rings = []
    for i, p in enumerate(path):
        n = normals[i]
        across = n.cross(tans[i])
        if across.length < 1e-9:
            across = Vector((1, 0, 0))
        across.normalize()
        hw = halfwidths[i]
        section = []
        for k in range(steps + 1):
            s = -1.0 + 2.0 * k / steps
            section.append((s, +thickness * 0.5))
        for k in range(1, arc + 1):
            a = math.pi * 0.5 * k / (arc + 1)
            section.append((1.0, thickness * 0.5 * math.cos(a)))
        for k in range(steps + 1):
            s = 1.0 - 2.0 * k / steps
            section.append((s, -thickness * 0.5))
        for k in range(1, arc + 1):
            a = math.pi * 0.5 * k / (arc + 1)
            section.append((-1.0, -thickness * 0.5 * math.cos(a)))
        ring = []
        for s, h in section:
            bulge = fold * hw * (1.0 - s * s)
            thick = h * (1.0 + edge * s)
            ring.append(p + across * (s * hw)
                        + n * (thick + bulge + dish * hw * s))
        rings.append(ring)
    verts = [v for ring in rings for v in ring]
    m = len(rings[0])
    faces = []
    for i in range(len(rings) - 1):
        a, b = i * m, (i + 1) * m
        for j in range(m):
            j2 = (j + 1) % m
            faces.append((a + j, a + j2, b + j2, b + j))
    for idx, rev in ((0, True), (len(rings) - 1, False)):
        base = idx * m
        c = sum(rings[idx], Vector()) / m
        ci = len(verts)
        verts.append(c)
        for j in range(m):
            j2 = (j + 1) % m
            faces.append((base + j2, base + j, ci) if rev else (base + j, base + j2, ci))
    return verts, faces


def add_mesh(name, verts, faces):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in verts], [], faces)
    me.validate()
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def clean(ob):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(ob.data)
    bm.free()


def shade(ob, angle=42.0):
    for poly in ob.data.polygons:
        poly.use_smooth = True
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    try:
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(angle))
    except Exception as exc:
        print("shade fail", exc)


def loop_obj(side):
    pts = catmull(LOOP_CTRL, P["loop_samples"])
    path = [Vector((p.x * side, p.y, 0.0)) for p in pts]
    hw = []
    n = len(path)
    for i in range(n):
        u = i / (n - 1)
        # pinch the ribbon where it enters the knot, widest over the outer half
        k = 0.12 + 0.88 * math.sin(math.pi * u) ** 0.45
        hw.append(P["band_w"] * 0.5 * k)
    nrm = [Vector((0, 0, 1))] * n
    v, f = sweep(path, nrm, hw, P["fold"], P["band_t"],
                 dish=P["loop_dish"], edge=P["loop_edge"])
    ob = add_mesh("Loop%s" % ("L" if side > 0 else "R"), v, f)
    ob.matrix_world = (Matrix.Rotation(math.radians(-P["loop_tilt_deg"]), 4, "X")
                       @ Matrix.Rotation(math.radians(P["loop_splay_deg"] * side), 4, "Y"))
    return ob


def tail_obj(side):
    ctrl = [
        Vector((0.015 * side, -0.012)),
        Vector((0.023 * side, -0.050)),
        Vector((0.032 * side, -0.090)),
        Vector((0.038 * side, -0.124)),
    ]
    pts = catmull(ctrl, 28)
    path = [Vector((p.x, p.y, 0.0)) for p in pts]
    hw = [P["tail_w"] * 0.5 * (1.0 - 0.16 * (i / (len(path) - 1))) for i in range(len(path))]
    nrm = [Vector((0, 0, 1))] * len(path)
    v, f = sweep(path, nrm, hw, P["fold"] * 0.7, P["band_t"])
    ob = add_mesh("Tail%s" % ("L" if side > 0 else "R"), v, f)
    ob.matrix_world = Matrix.Rotation(math.radians(-6.0 * side), 4, "Y")
    return ob


def cut_notch(tail, side):
    tip_y = -0.131
    apex_y = tip_y + P["tail_notch"]
    x = 0.038 * side
    half = P["tail_notch_w"] * 0.5
    h = 0.02
    v = [Vector((x - half, tip_y - 0.03, -h)), Vector((x + half, tip_y - 0.03, -h)),
         Vector((x, apex_y, -h)),
         Vector((x - half, tip_y - 0.03, h)), Vector((x + half, tip_y - 0.03, h)),
         Vector((x, apex_y, h))]
    f = [(0, 1, 2), (5, 4, 3), (0, 3, 4), (0, 4, 1), (1, 4, 5), (1, 5, 2),
         (2, 5, 3), (2, 3, 0)]
    cut = add_mesh("cut", v, f)
    clean(cut)
    bpy.ops.object.select_all(action="DESELECT")
    tail.select_set(True)
    bpy.context.view_layer.objects.active = tail
    mod = tail.modifiers.new("notch", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.object = cut
    mod.solver = "FAST"
    bpy.ops.object.modifier_apply(modifier="notch")
    bpy.data.objects.remove(cut, do_unlink=True)
    return tail


def knot_obj():
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, P["knot"][2] * 0.5 - 0.006))
    ob = bpy.context.object
    ob.name = "Knot"
    ob.scale = P["knot"]
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    mod = ob.modifiers.new("bev", "BEVEL")
    mod.width = P["knot_bevel"]
    mod.segments = 4
    mod.limit_method = "NONE"
    bpy.ops.object.modifier_apply(modifier="bev")
    return ob


def strap_obj():
    r = R_NOMINAL - P["strap_sink"]
    n = 28
    path, norms = [], []
    for i in range(n + 1):
        a = math.pi * 2.0 * i / n
        path.append(Vector((math.sin(a) * r, 0.0, -R_NOMINAL + math.cos(a) * r)))
        norms.append(Vector((math.sin(a), 0, math.cos(a))))
    hw = [P["strap_w"] * 0.5] * len(path)
    v, f = sweep(path, norms, hw, 0.0, P["strap_t"])
    return add_mesh("Strap", v, f)


def build(parts=("loops", "tails", "knot")):
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    made = []
    if "loops" in parts:
        made += [loop_obj(1), loop_obj(-1)]
    if "tails" in parts:
        for side in (1, -1):
            made.append(cut_notch(tail_obj(side), side))
    if "knot" in parts:
        made.append(knot_obj())
    if "strap" in parts:
        made.append(strap_obj())
    for ob in made:
        clean(ob)
        shade(ob)
    return made


def join(parts):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.object
    ob.name = "TailBow"
    return ob


def material(ob):
    mat = bpy.data.materials.get("TailBowSatin")
    if mat is None:
        mat = bpy.data.materials.new("TailBowSatin")
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (0.45, 0.006, 0.018, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.50
    bsdf.inputs["Specular IOR Level"].default_value = 0.45
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def studio():
    scn = bpy.context.scene
    try:
        scn.render.engine = "BLENDER_EEVEE_NEXT"
    except Exception:
        scn.render.engine = "BLENDER_EEVEE"
    scn.render.resolution_x = 900
    scn.render.resolution_y = 900
    scn.render.film_transparent = False
    w = bpy.data.worlds[0] if bpy.data.worlds else bpy.data.worlds.new("W")
    scn.world = w
    w.use_nodes = True
    bg = next(n for n in w.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs[0].default_value = (0.16, 0.16, 0.17, 1)
    bg.inputs[1].default_value = 1.0
    for name, loc, power, size, rot in (
        ("key", (0.30, -0.40, 0.40), 18, 0.35, (52, 0, 30)),
        ("fill", (-0.40, -0.30, 0.10), 7, 0.55, (85, 0, -50)),
        ("rim", (0.0, 0.38, 0.25), 10, 0.35, (-120, 0, 0)),
    ):
        if bpy.data.objects.get(name):
            continue
        d = bpy.data.lights.new(name, "AREA")
        d.energy = power
        d.size = size
        o = bpy.data.objects.new(name, d)
        o.location = loc
        o.rotation_euler = [math.radians(a) for a in rot]
        scn.collection.objects.link(o)


def shoot(name, loc, target=(0, 0, -0.012), lens=70.0):
    scn = bpy.context.scene
    cam = bpy.data.objects.get("Cam")
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        scn.collection.objects.link(cam)
    cam.data.lens = lens
    cam.location = loc
    cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    scn.camera = cam
    scn.render.filepath = os.path.join(OUT, "bow_%s.png" % name)
    bpy.ops.render.render(write_still=True)
    return scn.render.filepath


def render_all(tag=""):
    studio()
    return [shoot(tag + k, Vector(v)) for k, v in {
        "front": (0.0, -0.62, 0.0),
        "threeq": (0.34, -0.52, 0.12),
        "side": (0.62, 0.0, 0.0),
        "top": (0.0, 0.0, 0.62),
        "bottom": (0.0, 0.0, -0.62),
        "close": (0.06, -0.22, 0.0),
    }.items()]


def orient(ob):
    """Rotate into Blender-native orientation: +Z up, face toward -Y.

    glTF export then yields +Y up, +Z out, which is the frame the runtime uses.
    """
    ob.matrix_world = Matrix.Rotation(math.radians(90.0), 4, "X") @ ob.matrix_world
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


GLB_NAME = os.path.join("assets", "tail_bow", "tail_bow.glb")


def default_glb_path():
    here = globals().get("__file__")
    if here:
        root = os.path.abspath(os.path.join(os.path.dirname(here), "..", ".."))
        return os.path.join(root, GLB_NAME)
    return os.path.expanduser("~/Documents/projects/home-equestria/mods/unfplap/" + GLB_NAME)


def export_glb(ob, path=None):
    """Write the one mesh piece the runtime loads, in glTF's +Y-up frame."""
    path = path or default_glb_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)
    print("EXPORTED", path, os.path.getsize(path), "bytes")
    return path


def report(obs):
    from mathutils import Vector as V
    for ob in obs:
        bb = [ob.matrix_world @ V(c) for c in ob.bound_box]
        xs = [v.x for v in bb]
        ys = [v.y for v in bb]
        zs = [v.z for v in bb]
        print("PART", ob.name, "tris", len(ob.data.polygons),
              "x %.3f %.3f  y %.3f %.3f  z %.3f %.3f"
              % (min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))


if not globals().get("NO_MAIN"):
    parts = build()
    report(parts)
    bow = join(parts)
    orient(bow)
    material(bow)
    print("BOW_TRIS", len(bow.data.polygons), "VERTS", len(bow.data.vertices))
    export_glb(bow)
    if not globals().get("NO_RENDER"):
        print("RENDERS", render_all())
