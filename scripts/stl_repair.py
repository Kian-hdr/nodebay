"""Nodebay's GPL-3.0 local Blender adapter, not a modification of Blender.

Only staged STL data is parsed. No blend files, add-ons, URLs or user scripts.
Report fields are counts/categories, never names, paths or coordinates.
"""
import argparse
import collections
import json
import math
import os
import pathlib
import resource
import struct
import sys
import threading
import time

PINNED_VERSION = "5.0.1"
MAX_BYTES = 32 * 1024 * 1024
MAX_TRIANGLES = 200_000


class InvalidMesh(Exception):
    pass


def read_stl(path):
    size = path.stat().st_size
    if not 0 < size <= MAX_BYTES or path.is_symlink():
        raise InvalidMesh("input_limit")
    data = path.read_bytes()
    triangles, normals, warnings = [], [], []
    # Prefer a binary structural match even if its header begins with 'solid'.
    declared = struct.unpack_from("<I", data, 80)[0] if size >= 84 else 0
    binary = size >= 84 and (84 + 50 * declared == size or not data.lstrip().lower().startswith(b"solid"))
    if binary:
        if declared > MAX_TRIANGLES:
            raise InvalidMesh("triangle_limit")
        available = (size - 84) // 50
        if (size - 84) % 50 or available == 0 or available > MAX_TRIANGLES:
            raise InvalidMesh("truncated_binary")
        if declared != available:
            warnings.append("binary_count_corrected")
        for offset in range(84, size, 50):
            values = struct.unpack_from("<12fH", data, offset)
            normals.append(tuple(values[:3]))
            triangles.append(tuple(tuple(values[i:i + 3]) for i in (3, 6, 9)))
    else:
        try:
            lines = data.decode("ascii").splitlines()
            state, vertices, normal = "solid", [], None
            for line in lines:
                words = line.strip().split()
                if not words:
                    continue
                key = words[0].lower()
                if state == "solid" and key == "solid": state = "facet"
                elif state == "facet" and key == "endsolid": state = "end"
                elif state == "facet" and len(words) == 5 and words[:2] == ["facet", "normal"]:
                    normal = tuple(map(float, words[2:])); state = "loop"
                elif state == "loop" and words == ["outer", "loop"]: state = "vertices"; vertices = []
                elif state == "vertices" and key == "vertex" and len(words) == 4 and len(vertices) < 3:
                    vertices.append(tuple(map(float, words[1:])))
                elif state == "vertices" and words == ["endloop"] and len(vertices) == 3: state = "endfacet"
                elif state == "endfacet" and words == ["endfacet"]:
                    triangles.append(tuple(vertices)); normals.append(normal); state = "facet"
                    if len(triangles) > MAX_TRIANGLES: raise InvalidMesh("triangle_limit")
                else: raise InvalidMesh("malformed_ascii")
            if state == "facet" and triangles: warnings.append("missing_ascii_footer")
            elif state != "end": raise InvalidMesh("malformed_ascii")
        except (ValueError, UnicodeError):
            raise InvalidMesh("malformed_ascii") from None
    if not triangles:
        raise InvalidMesh("empty_mesh")
    # Blender stores coordinates as float32. Reject overflow, NaN and infinity.
    for triangle in triangles:
        for vertex in triangle:
            if any(not math.isfinite(v) or abs(v) > 1e12 for v in vertex):
                raise InvalidMesh("invalid_coordinates")
    return triangles, normals, warnings


def cross(triangle):
    a, b, c = triangle
    u, v = [b[i] - a[i] for i in range(3)], [c[i] - a[i] for i in range(3)]
    return (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])


def analyze(triangles, normals):
    vertices, edges, faces = set(), collections.defaultdict(list), set()
    degenerate = duplicates = normal_errors = 0
    adjacency = collections.defaultdict(set)
    for index, triangle in enumerate(triangles):
        vertices.update(triangle)
        n = cross(triangle)
        area = sum(v*v for v in n)
        if area == 0: degenerate += 1
        key = tuple(sorted(triangle))
        if key in faces: duplicates += 1
        faces.add(key)
        given = normals[index]
        if area > 0 and (any(not math.isfinite(v) for v in given) or sum(n[i]*given[i] for i in range(3)) <= 0): normal_errors += 1
        for a, b in zip(triangle, triangle[1:] + triangle[:1]):
            edges[tuple(sorted((a, b)))].append((index, a < b))
    boundary = collections.defaultdict(set)
    nonmanifold = winding = 0
    for (a, b), uses in edges.items():
        if len(uses) == 1: boundary[a].add(b); boundary[b].add(a)
        if len(uses) > 2: nonmanifold += 1
        if len(uses) == 2 and uses[0][1] == uses[1][1]: winding += 1
        first = uses[0][0]
        for face, _ in uses[1:]: adjacency[first].add(face); adjacency[face].add(first)
    def groups(nodes, graph):
        remaining, result = set(nodes), []
        while remaining:
            first = remaining.pop(); group = {first}; queue = [first]
            while queue:
                for neighbor in graph.get(queue.pop(), ()):
                    if neighbor in remaining: remaining.remove(neighbor); group.add(neighbor); queue.append(neighbor)
            result.append(group)
        return result
    holes = sum(all(len(boundary[v]) == 2 for v in group) for group in groups(boundary, boundary))
    return dict(triangles=len(triangles), vertices=len(vertices), holes=holes,
                boundary_edges=sum(len(v) for v in boundary.values())//2,
                non_manifold_edges=nonmanifold, degenerate_faces=degenerate,
                duplicate_faces=duplicates, normal_errors=normal_errors, winding_edges=winding,
                components=len(groups(range(len(triangles)), adjacency)))


def bounds(triangles):
    return [func(v[i] for t in triangles for v in t) for func in (min, max) for i in range(3)]


def write_stl(path, triangles):
    with path.open("xb") as output:
        output.write(b"Nodebay local structural repair".ljust(80, b"\0"))
        output.write(struct.pack("<I", len(triangles)))
        for triangle in triangles:
            n = cross(triangle); length = math.sqrt(sum(v*v for v in n))
            if not length: raise InvalidMesh("invalid_output")
            output.write(struct.pack("<12fH", *(v/length for v in n), *(v for p in triangle for v in p), 0))
        output.flush(); os.fsync(output.fileno())


def repair(job, mode):
    import bpy
    import bmesh
    if bpy.app.version_string != PINNED_VERSION: raise InvalidMesh("engine_version_mismatch")
    triangles, normals, warnings = read_stl(job / "input.stl")
    before = analyze(triangles, normals)
    report = dict(engine=PINNED_VERSION, mode=mode, before=before, after=before,
                  status="inspected", holes_closed=0, normals_corrected=0,
                  removed_duplicates=0, removed_degenerate=0, remeshed=False,
                  geometry_changed=False, scale_changed=False, warnings=warnings,
                  self_intersections="not_tested", input_bytes=(job / "input.stl").stat().st_size,
                  output_bytes=0)
    if mode == "inspect": return report
    bm = bmesh.new()
    try:
        verts, seen = {}, set()
        for triangle in triangles:
            if sum(v*v for v in cross(triangle)) == 0: continue
            key = tuple(sorted(triangle))
            if key in seen: continue
            seen.add(key)
            face_verts = []
            for point in triangle:
                if point not in verts: verts[point] = bm.verts.new(point)
                face_verts.append(verts[point])
            try: bm.faces.new(face_verts)
            except ValueError: raise InvalidMesh("unrecoverable_topology") from None
        if not bm.faces: raise InvalidMesh("no_valid_triangles")
        bm.normal_update()
        old_normals = {face: face.normal.copy() for face in bm.faces}
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        report["normals_corrected"] = sum(face.normal.dot(old) < 0 for face, old in old_normals.items()) + before["normal_errors"]
        if mode == "thorough":
            bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=0)
            bmesh.ops.triangulate(bm, faces=list(bm.faces))
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        output = [tuple(tuple(float(v) for v in vertex.co) for vertex in face.verts) for face in bm.faces]
        if not 0 < len(output) <= MAX_TRIANGLES or any(len(t) != 3 for t in output): raise InvalidMesh("output_limit")
        # No coordinate scaling or remeshing. Float32 roundoff tolerance only.
        original_bounds, new_bounds = bounds(triangles), bounds(output)
        tolerance = max(1e-6, max(abs(v) for v in original_bounds) * 2e-7)
        if any(abs(a-b) > tolerance for a,b in zip(original_bounds, new_bounds)):
            raise InvalidMesh("bounds_changed")
        write_stl(job / "output.stl", output)
        checked, output_normals, _ = read_stl(job / "output.stl")
        after = analyze(checked, output_normals)
        report.update(after=after, holes_closed=max(0, before["holes"]-after["holes"]),
                      removed_duplicates=before["duplicate_faces"], removed_degenerate=before["degenerate_faces"],
                      geometry_changed=len(checked) != len(triangles) or mode == "thorough" and before["boundary_edges"] != after["boundary_edges"],
                      output_bytes=(job / "output.stl").stat().st_size)
        unresolved = any(after[k] for k in ("boundary_edges", "non_manifold_edges", "degenerate_faces", "duplicate_faces", "winding_edges"))
        report["status"] = "partial" if unresolved or after["components"] > 1 else "repaired"
        if unresolved: warnings.append("structural_defects_remain")
        if after["components"] > 1: warnings.append("components_preserved")
        warnings.append("self_intersections_not_tested")
        return report
    finally: bm.free()


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", required=True)
    parser.add_argument("--mode", choices=["safe", "thorough", "inspect"], required=True)
    options = parser.parse_args(args)
    job = pathlib.Path(options.job)
    started = time.monotonic()
    # CPU hard cap plus watchdog: macOS ignores RLIMIT_RSS, so measure peak RSS.
    resource.setrlimit(resource.RLIMIT_CPU, (120, 125))
    def watchdog():
        while True:
            if time.monotonic() - started > 150 or resource.getrusage(resource.RUSAGE_SELF).ru_maxrss > 2 * 1024**3:
                os._exit(72)
            time.sleep(0.2)
    threading.Thread(target=watchdog, daemon=True).start()
    try:
        if not job.is_dir() or job.is_symlink(): raise InvalidMesh("invalid_job")
        report = repair(job, options.mode)
        report["duration"] = round(time.monotonic() - started, 3)
        with (job / "report.json").open("x") as handle: json.dump(report, handle, sort_keys=True, allow_nan=False)
    except Exception as error:
        # Never print Python exceptions, traceback, model content or user paths.
        category = str(error) if isinstance(error, InvalidMesh) else "engine_failure"
        print("NODEBAY_STL_ERROR:" + category)
        sys.exit(7)


if __name__ == "__main__": main()
