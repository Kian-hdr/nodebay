import pathlib
import subprocess
import tempfile
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SERVICE = ROOT / "boringNotch/components/Shelf/Services/ShelfPersistenceService.swift"


class ShelfPersistenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.executable = pathlib.Path(cls.directory.name) / "shelf-persistence"
        subprocess.run(
            ["swiftc", "-swift-version", "5", "-strict-concurrency=targeted",
             str(SERVICE), str(ROOT / "tests/ShelfPersistenceHarness.swift"),
             "-o", str(cls.executable)],
            check=True, capture_output=True, text=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def run_case(self, case):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [str(self.executable), case, directory], timeout=20,
                capture_output=True, text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("checks passed", result.stdout)

    def test_flush_waits_for_cancelled_older_async_write(self):
        self.run_case("cancelled-write")

    def test_pending_saves_keep_admission_order_before_flush(self):
        self.run_case("ordered-writes")

    def test_round_trip_partial_recovery_and_failed_encode_preserve_file(self):
        self.run_case("round-trip")

    def test_actual_shelf_codable_model_compiles_and_round_trips(self):
        # Compile the actual model's stored properties, Codable implementation,
        # and actor annotations without unrelated AppKit thumbnail dependencies.
        model = (ROOT / "boringNotch/components/Shelf/Models/ShelfItem.swift").read_text()
        model = model.split("    var displayName: String", 1)[0] + "}\n"
        with tempfile.TemporaryDirectory() as directory:
            folder = pathlib.Path(directory)
            (folder / "Model.swift").write_text(model)
            (folder / "Main.swift").write_text('''import Foundation
@main struct Main {
    @MainActor static func main() async {
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("items.json")
        let service = ShelfPersistenceService(fileURL: file)
        let members = [ShelfItem(kind: .text(string: "Saved draft 🗂️")),
                       ShelfItem(kind: .file(bookmark: Data([0, 1, 2])), isTemporary: true),
                       ShelfItem(kind: .link(url: URL(string: "https://example.com")!))]
        let items = [ShelfItem(kind: .stack(name: "Results", members: members))]
        await service.saveAsync(items)
        precondition(service.load() == items)
        service.save(members)
        precondition(service.load() == members)
        print("Actual shelf model checks passed")
    }
}
''')
            executable = folder / "actual-model"
            subprocess.run(
                ["swiftc", "-swift-version", "5", "-strict-concurrency=targeted",
                 str(SERVICE), str(folder / "Model.swift"), str(folder / "Main.swift"),
                 "-o", str(executable)], check=True, capture_output=True, text=True,
            )
            result = subprocess.run([str(executable), directory], check=True, timeout=20,
                                    capture_output=True, text=True)
            self.assertIn("Actual shelf model checks passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
