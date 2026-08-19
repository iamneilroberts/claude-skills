import json, os, sys, tempfile, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
sys.path.insert(0, os.path.join(HERE, "..", "sinks"))
import aggregate, local_report  # noqa: E402

def load():
    with open(os.path.join(HERE, "fixtures", "judged_ok.json")) as f:
        return json.load(f)

class TestLocalReport(unittest.TestCase):
    def test_render_contains_verdicts_and_summary(self):
        results = load()
        md = local_report.render(results, aggregate.summarize(results))
        self.assertIn("budget-traveler", md)
        self.assertIn("FAIL", md)
        self.assertIn("worst_severity", md)

    def test_write_creates_file_under_runs_dir(self):
        results = load()
        with tempfile.TemporaryDirectory() as d:
            path = local_report.write(results, d, "run-123")
            self.assertTrue(os.path.exists(path))
            self.assertIn("run-123", path)

    def test_write_resolves_aggregate_without_lib_on_syspath(self):
        import subprocess, sys, tempfile, os, json
        SINKS = os.path.join(HERE, "..", "sinks")
        with tempfile.TemporaryDirectory() as d:
            script = (
                "import sys, json; sys.path.insert(0, %r);\n"
                "import local_report;\n"
                "p = local_report.write([], %r, 'run-x');\n"
                "print(p)" % (SINKS, d)
            )
            out = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertIn("run-x", out.stdout)

if __name__ == "__main__":
    unittest.main()
