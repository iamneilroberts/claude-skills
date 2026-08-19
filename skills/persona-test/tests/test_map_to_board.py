import os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "adapters", "voygent"))
import map_to_board as m  # noqa: E402

def result(**kw):
    base = {"personaId": "p", "scenario": "s",
            "scores": {"comprehension": 5, "elicitation": 4, "free_surface": 3, "funnel": 2},
            "verdict": "pass", "severity": "none", "rationale": "",
            "fabricationCount": 0, "crossCheckPassed": True, "terminatedBy": "completed"}
    base.update(kw); return base

class TestMapToBoard(unittest.TestCase):
    def test_row_carries_board_dimensions(self):
        body = m.map_to_board("run-1", "2026-08-18", [result()])
        row = body["rows"][0]
        self.assertEqual(set(row["scores"]), {"comprehension", "elicitation", "free_surface", "funnel"})
        self.assertEqual(row["scores"]["comprehension"], 5)
        self.assertEqual(row["fabricationCount"], 0)
        self.assertIs(row["crossCheckPassed"], True)
        self.assertEqual(row["terminatedBy"], "completed")

    def test_caps_are_enforced(self):
        body = m.map_to_board("R" * 200, "D" * 60, [result(scenario="X" * 200)])
        self.assertLessEqual(len(body["runId"]), 120)
        self.assertLessEqual(len(body["date"]), 40)
        self.assertLessEqual(len(body["rows"][0]["scenario"]), 120)

    def test_rows_are_batched_and_capped_at_200(self):
        body = m.map_to_board("run-1", "2026-08-18", [result() for _ in range(250)])
        self.assertLessEqual(len(body["rows"]), 200)

    def test_issues_normalized_and_invalid_dropped(self):
        issues = [
            {"number": 42, "url": "https://gh/42", "status": "open", "title": "bug"},
            {"number": 0, "url": "https://gh/x", "status": "open"},          # number<=0 -> drop
            {"number": 5, "url": "http://insecure", "status": "open"},        # not https -> drop
            {"number": 6, "url": "https://gh/6", "status": "bogus"},          # bad status -> drop
        ]
        body = m.map_to_board("run-1", "2026-08-18", [result()], issues=issues)
        self.assertEqual(len(body["issues"]), 1)
        self.assertEqual(body["issues"][0]["number"], 42)

if __name__ == "__main__":
    unittest.main()
