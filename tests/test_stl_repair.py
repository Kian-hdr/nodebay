"""Synthetic local fixtures. Blender runs offline and behind a network deny rule."""
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/stl_repair.py"
BLENDER = Path("/Applications/Blender.app/Contents/MacOS/Blender")
spec = importlib.util.spec_from_file_location("stl_repair", SCRIPT)
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
# Outward winding tetrahedron, no third-party/proprietary assets.
A, B, C, D = (0.,0.,0.), (10.,0.,0.), (0.,10.,0.), (0.,0.,10.)
TETRA = [(A,C,B), (A,B,D), (A,D,C), (B,C,D)]

def binary(triangles, declared=None):
    data = b"Nodebay test".ljust(80, b"\0") + struct.pack("<I", len(triangles) if declared is None else declared)
    for t in triangles:
        n = adapter.cross(t)
        data += struct.pack("<12fH", *n, *(v for p in t for v in p), 0)
    return data


class STLParserTests(unittest.TestCase):
    def test_binary_ascii_and_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            p = Path(directory)/"fixture.stl"
            p.write_bytes(binary(TETRA))
            triangles, normals, warnings = adapter.read_stl(p)
            self.assertEqual(triangles, TETRA)
            self.assertEqual(adapter.analyze(triangles,normals)["holes"], 0)
            for data in [b"", b"solid broken", binary(TETRA)[:-1], binary(TETRA, 0xffffffff)]:
                p.write_bytes(data)
                with self.assertRaises(adapter.InvalidMesh): adapter.read_stl(p)
            p.write_text("solid test\nfacet normal 0 0 1\nouter loop\nvertex 0 0 0\nvertex 1 0 0\nvertex 0 1 0\nendloop\nendfacet\nendsolid test\n")
            self.assertEqual(len(adapter.read_stl(p)[0]), 1)

    def test_defect_analysis(self):
        for tris, key in [(TETRA[:-1],"holes"), (TETRA+[TETRA[0]],"duplicate_faces"), (TETRA+[(A,A,B)],"degenerate_faces"), (TETRA+[tuple(reversed(TETRA[0]))],"non_manifold_edges")]:
            self.assertGreater(adapter.analyze(tris,[adapter.cross(t) for t in tris])[key],0)
        inverted = [tuple(reversed(TETRA[0]))]+TETRA[1:]
        self.assertGreater(adapter.analyze(inverted,[adapter.cross(t) for t in inverted])["winding_edges"],0)

    def test_recoverable_structure(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"f.stl"; p.write_bytes(binary(TETRA, 3))
            self.assertIn("binary_count_corrected", adapter.read_stl(p)[2])


@unittest.skipUnless(BLENDER.exists(), "Blender 5.0.1 companion unavailable")
class STLBlenderTests(unittest.TestCase):
    def run_engine(self, triangles, mode="safe", raw=None):
        directory = tempfile.TemporaryDirectory(prefix="nodebay-stl-test-")
        self.addCleanup(directory.cleanup)
        job=Path(directory.name)
        source=job/"source ü spaces.stl"; source.write_bytes(raw if raw is not None else binary(triangles))
        before=hashlib.sha256(source.read_bytes()).hexdigest()
        shutil.copyfile(source, job/"input.stl")
        args=["/usr/bin/sandbox-exec","-p","(version 1) (allow default) (deny network*)",str(BLENDER),"--background","--factory-startup","--disable-autoexec","--offline-mode","--threads","2","--python-exit-code","7","--python",str(SCRIPT),"--","--mode",mode,"--job",str(job)]
        result=subprocess.run(args, capture_output=True, text=True, timeout=30)
        self.assertEqual(before,hashlib.sha256(source.read_bytes()).hexdigest())
        if result.returncode:
            return None,job,result
        report=json.loads((job/"report.json").read_text())
        self.assertNotIn(source.name,json.dumps(report))
        self.assertNotIn(str(job),json.dumps(report))
        return report,job,result

    def test_valid_deterministic_binary_preserves_bounds(self):
        r,a,p=self.run_engine(TETRA); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        r2,b,p2=self.run_engine(TETRA)
        self.assertEqual(r["status"],"repaired")
        self.assertEqual((a/"output.stl").read_bytes(),(b/"output.stl").read_bytes())
        self.assertEqual(adapter.bounds(adapter.read_stl(a/"output.stl")[0]),adapter.bounds(TETRA))

    def test_safe_open_is_partial_thorough_fills_with_no_scale_change(self):
        r,j,p=self.run_engine(TETRA[:-1]); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(r["status"],"partial"); self.assertEqual(r["holes_closed"],0)
        r,j,p=self.run_engine(TETRA[:-1],"thorough"); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(r["after"]["holes"],0); self.assertEqual(r["holes_closed"],1)
        self.assertFalse(r["scale_changed"])

    def test_duplicate_degenerate_and_inverted_normals(self):
        r,j,p=self.run_engine([tuple(reversed(TETRA[0]))]+TETRA[1:]+[TETRA[1],(A,A,B)])
        self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(r["after"]["triangles"],4)
        self.assertEqual(r["removed_duplicates"],1); self.assertEqual(r["removed_degenerate"],1)
        self.assertEqual(r["after"]["winding_edges"],0)

    def test_components_preserved_and_inspection_writes_no_model(self):
        shifted=[tuple(tuple(v[i]+30 for i in range(3)) for v in t) for t in TETRA]
        r,j,p=self.run_engine(TETRA+shifted); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertEqual(r["after"]["components"],2); self.assertEqual(r["status"],"partial")
        r,j,p=self.run_engine(TETRA,"inspect"); self.assertEqual(p.returncode,0,p.stdout+p.stderr)
        self.assertFalse((j/"output.stl").exists())

    def test_malformed_input_is_redacted_failure(self):
        r,j,p=self.run_engine([],raw=b"bad data PRIVATE MODEL SENTINEL")
        self.assertNotEqual(p.returncode,0)
        self.assertNotIn("PRIVATE MODEL SENTINEL",p.stdout+p.stderr)
        self.assertFalse((j/"output.stl").exists())


class STLIntegrationContracts(unittest.TestCase):
    def test_local_isolation_and_approval(self):
        helper=(ROOT/"BoringNotchXPCHelper/BoringNotchXPCHelper.swift").read_text()
        self.assertIn("(deny network*)",helper)
        self.assertIn('"--disable-autoexec", "--offline-mode"',helper)
        self.assertIn('UUID(uuidString: job.lastPathComponent)',helper)
        service=(ROOT/"boringNotch/components/Shelf/Services/STLRepairService.swift").read_text()
        self.assertIn('mode != .thorough || confirmed',service)
        self.assertIn('copyItem(at: source',service)
        self.assertIn('link(staged.path, output.path)',service)
        self.assertIn('errno == EEXIST',service)
        self.assertNotIn('URLSession',service)
        self.assertNotIn('print(',service)
        coordinator=(ROOT/"boringNotch/components/Shelf/Services/STLRepairCoordinator.swift").read_text()
        self.assertIn('alert.runModal() == .alertSecondButtonReturn',coordinator)
        self.assertIn('case .file', (ROOT/"boringNotch/components/Shelf/Models/ShelfItem.swift").read_text())
        self.assertIn('insertResult(result, beside: source)',coordinator)
        self.assertIn('Task.isCancelled',coordinator)
        self.assertIn('Unavailable; no uploads implemented',coordinator)
        self.assertNotIn('URLSession',coordinator)
        for path in ["Models/Bookmark.swift", "Views/ShelfItemView.swift", "ViewModels/ShelfStateViewModel.swift"]:
            for line in (ROOT/"boringNotch/components/Shelf"/path).read_text().splitlines():
                if "NSLog(" in line or "print(" in line:
                    self.assertNotIn("url.path",line)
                    self.assertNotIn('\\(item)',line)


@unittest.skipUnless(BLENDER.exists() and shutil.which("swiftc"), "Requires macOS Swift and Blender 5.0.1")
class STLServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory(prefix="nodebay-stl-service-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root=Path(cls.temp.name)
        cls.harness=cls.root/"harness"
        result=subprocess.run(["swiftc", str(ROOT/"tests/STLRepairHarness.swift"), str(ROOT/"boringNotch/components/Shelf/Services/STLRepairService.swift"), "-o", str(cls.harness)],capture_output=True,text=True)
        if result.returncode: raise AssertionError(result.stderr)

    def setUp(self):
        self.directory=tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.directory.cleanup)
        self.folder=Path(self.directory.name)
        self.source=self.folder/"part ü ; $(echo not-shell).stl"
        self.source.write_bytes(binary(TETRA))
        self.outputs=self.folder/"managed"

    def run_service(self,mode="safe"):
        before=self.source.read_bytes()
        result=subprocess.run([str(self.harness),mode,str(self.source),str(self.outputs),str(SCRIPT)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(self.source.read_bytes(),before)
        self.assertFalse(list((self.outputs/"STLJobs").glob("*")))
        return json.loads(result.stdout)

    def test_collision_atomic_persistence_and_unicode(self):
        a=self.run_service(); b=self.run_service()
        self.assertIn("output",a,a); self.assertIn("output",b,b)
        self.assertNotEqual(a["output"],b["output"])
        self.assertTrue(a["output"].endswith("-repaired.stl"))
        self.assertTrue(b["output"].endswith("-repaired-2.stl"))
        self.assertEqual(Path(a["output"]).read_bytes(),Path(b["output"]).read_bytes())
        self.assertEqual(len(adapter.read_stl(Path(a["output"]))[0]),4)

    def test_cancel_timeout_crash_missing_engine_and_confirmation(self):
        for mode in ["cancel","timeout","crash","missing","thorough-unconfirmed"]:
            with self.subTest(mode=mode):
                result=self.run_service(mode)
                self.assertIn("error",result)
                self.assertNotIn("private",result["error"])
                self.assertFalse(list((self.outputs/"Repaired Models").glob("*")))

    def test_inspection_no_generated_output(self):
        result=self.run_service("inspect")
        self.assertEqual(result["output"],"")
        self.assertFalse((self.outputs/"Repaired Models").exists())

    def test_actual_batch_coordinator_preserves_partial_success(self):
        executable=self.folder/"coordinator"
        result=subprocess.run(["swiftc", "-DSTL_COORDINATOR_TEST", str(ROOT/"tests/STLRepairHarness.swift"), str(ROOT/"tests/STLRepairCoordinatorHarness.swift"), str(ROOT/"boringNotch/components/Shelf/Services/STLRepairService.swift"), str(ROOT/"boringNotch/components/Shelf/Services/STLRepairCoordinator.swift"), "-o", str(executable)], capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stderr)
        result=subprocess.run([str(executable),"batch",str(self.source),str(self.outputs),str(SCRIPT)],capture_output=True,text=True,timeout=30)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn("partial-success fixtures passed",result.stdout)

if __name__ == "__main__": unittest.main()
