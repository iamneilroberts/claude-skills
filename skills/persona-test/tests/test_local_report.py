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

if __name__ == "__main__":
    unittest.main()
