import json, os, subprocess, sys, tempfile, unittest
HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "sinks"))
import http_post  # noqa: E402
HP = os.path.join(HERE, "..", "sinks", "http_post.py")

class TestHttpPost(unittest.TestCase):
    def test_build_request_sets_bearer_from_env(self):
        os.environ["FAKE_TOKEN"] = "sekret"
        url, headers, data = http_post.build_request(
            "https://x.test/ingest", "FAKE_TOKEN", {"runId": "r1"})
        self.assertEqual(headers["Authorization"], "Bearer sekret")
        self.assertIn("application/json", headers["Content-Type"])
        self.assertEqual(json.loads(data.decode()), {"runId": "r1"})

    def test_missing_token_env_errors(self):
        os.environ.pop("NO_SUCH_TOKEN", None)
        with self.assertRaises(RuntimeError):
            http_post.build_request("https://x.test", "NO_SUCH_TOKEN", {})

    def test_dry_run_makes_no_network_call_and_prints_body(self):
        os.environ["FAKE_TOKEN"] = "sekret"
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"runId": "r1", "rows": []}, f)
            body_path = f.name
        out = subprocess.run(
            [sys.executable, HP, "--url", "https://x.invalid/ingest",
             "--token-env", "FAKE_TOKEN", "--body", body_path, "--dry-run"],
            capture_output=True, text=True)
        self.assertEqual(out.returncode, 0)
        self.assertIn("r1", out.stdout)

if __name__ == "__main__":
    unittest.main()
