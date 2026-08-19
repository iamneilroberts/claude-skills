# tests/test_normalize.py
import os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import normalize  # noqa: E402

class TestNormalize(unittest.TestCase):
    def test_clamp_rounds_and_bounds(self):
        self.assertEqual(normalize.clamp_score(4.6), 5)
        self.assertEqual(normalize.clamp_score(-3), 0)
        self.assertEqual(normalize.clamp_score(99), 5)
        self.assertEqual(normalize.clamp_score("bad"), 0)

    def test_normalize_fills_defaults_and_derives_severity(self):
        raw = {"personaId": "p1", "scenario": "s",
               "scores": {"task_completion": 5, "correctness": 4, "ux_friction": 3},
               "verdict": "pass", "rationale": "ok"}
        out = normalize.normalize_judged(raw)
        self.assertEqual(out["verdict"], "pass")
        self.assertEqual(out["severity"], "none")
        self.assertEqual(out["scores"]["correctness"], 4)

    def test_fail_without_severity_defaults_to_major(self):
        raw = {"personaId": "p1", "scenario": "s", "scores": {},
               "verdict": "fail", "rationale": "broke"}
        out = normalize.normalize_judged(raw)
        self.assertEqual(out["verdict"], "fail")
        self.assertEqual(out["severity"], "major")
        self.assertEqual(out["scores"]["task_completion"], 0)

    def test_dimensions_override_preserves_adapter_scores(self):
        # Locks the normalize<->adapter-dimensions seam: an adapter (e.g. voygent) that
        # overrides judge dimensions must get its non-default scores back intact, not
        # zeroed under DEFAULT_DIMENSIONS keys the judge never populated.
        board_dims = ("comprehension", "elicitation", "free_surface", "funnel")
        raw = {"personaId": "p1", "scenario": "s",
               "scores": {"comprehension": 4, "elicitation": 3,
                           "free_surface": 5, "funnel": 2},
               "verdict": "pass", "rationale": "ok"}
        out = normalize.normalize_judged(raw, dimensions=board_dims)
        self.assertEqual(set(out["scores"]), set(board_dims))
        self.assertEqual(out["scores"]["comprehension"], 4)
        self.assertEqual(out["scores"]["elicitation"], 3)
        self.assertEqual(out["scores"]["free_surface"], 5)
        self.assertEqual(out["scores"]["funnel"], 2)

if __name__ == "__main__":
    unittest.main()
