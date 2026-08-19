import json, os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import aggregate  # noqa: E402

def load():
    with open(os.path.join(HERE, "fixtures", "judged_ok.json")) as f:
        return json.load(f)

class TestAggregate(unittest.TestCase):
    def test_counts_pass_fail(self):
        s = aggregate.summarize(load())
        self.assertEqual(s["total"], 2)
        self.assertEqual(s["passed"], 1)
        self.assertEqual(s["failed"], 1)

    def test_worst_severity_is_most_severe_failure(self):
        s = aggregate.summarize(load())
        self.assertEqual(s["worst_severity"], "blocker")

if __name__ == "__main__":
    unittest.main()
