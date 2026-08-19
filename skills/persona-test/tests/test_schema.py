import json, os, sys, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import schema  # noqa: E402

def fx(name):
    with open(os.path.join(HERE, "fixtures", name)) as f:
        return json.load(f)

class TestRunRecord(unittest.TestCase):
    def test_valid_run_record_has_no_errors(self):
        self.assertEqual(schema.validate_run_record(fx("run_record_ok.json")), [])

    def test_missing_scenario_reports_error(self):
        bad = fx("run_record_bad.json")  # missing "scenario"
        errs = schema.validate_run_record(bad)
        self.assertTrue(any("scenario" in e for e in errs))

    def test_non_object_reports_error(self):
        self.assertTrue(schema.validate_run_record("nope"))

    def test_judged_result_requires_scores_and_verdict(self):
        errs = schema.validate_judged_result({"personaId": "p1"})
        self.assertTrue(any("scores" in e for e in errs))
        self.assertTrue(any("verdict" in e for e in errs))

    def test_judged_result_bad_severity_reports_error(self):
        payload = {
            "personaId": "p1",
            "scenario": "book a stay",
            "scores": {},
            "verdict": "pass",
            "severity": "catastrophic",
            "rationale": "looks fine",
        }
        errs = schema.validate_judged_result(payload)
        self.assertTrue(any("severity" in e for e in errs))

        del payload["severity"]
        errs = schema.validate_judged_result(payload)
        self.assertTrue(any("severity" in e for e in errs))

    def test_judged_result_non_dict_scores_reports_error(self):
        payload = {
            "personaId": "p1",
            "scenario": "book a stay",
            "scores": [],
            "verdict": "pass",
            "severity": "none",
            "rationale": "looks fine",
        }
        errs = schema.validate_judged_result(payload)
        self.assertTrue(any("scores" in e for e in errs))

if __name__ == "__main__":
    unittest.main()
