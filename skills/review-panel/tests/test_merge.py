import json, os, subprocess, sys, unittest
HERE = os.path.dirname(__file__)
FIX = os.path.join(HERE, "fixtures")
MERGE = os.path.join(HERE, "..", "merge.py")
sys.path.insert(0, os.path.join(HERE, ".."))
import merge  # noqa: E402

def fx(*names): return [os.path.join(FIX, n) for n in names]

class TestClassify(unittest.TestCase):
    def test_dedup_merges_same_finding_across_models(self):
        vs = [merge.load_verdict(p) for p in fx("v_codex_bug.json", "v_gemini_bug.json")]
        merged = merge.dedup(vs)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["agreement"], 2)
        self.assertCountEqual(merged[0]["models"], ["codex", "gemini"])

    def test_dedup_merges_mixed_priority_takes_most_severe(self):
        # Same location, flagged CRITICAL(0) by codex and IMPORTANT(1) by gemini.
        # Location-only dedup MUST still merge them; merged priority is the min (0).
        vs = [merge.load_verdict(p) for p in fx("v_codex_bug.json", "v_gemini_bug_important.json")]
        merged = merge.dedup(vs)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["agreement"], 2)
        self.assertEqual(merged[0]["priority"], 0)

    def test_dedup_finding_key_is_order_independent(self):
        # Merged identity must be deterministic regardless of input file order,
        # so finding_key is stable between the classify and finalize phases.
        a = merge.dedup([merge.load_verdict(p) for p in fx("v_codex_bug.json", "v_gemini_bug.json")])
        b = merge.dedup([merge.load_verdict(p) for p in fx("v_gemini_bug.json", "v_codex_bug.json")])
        self.assertEqual(merge.finding_key(a[0]), merge.finding_key(b[0]))

    def test_classify_corroborated_has_no_lone_blocking(self):
        out = subprocess.run([sys.executable, MERGE, "--phase", "classify",
                              *fx("v_codex_bug.json", "v_gemini_bug.json", "v_claude_clean.json"),
                              "--block-at", "1"], capture_output=True, text=True)
        data = json.loads(out.stdout)
        self.assertEqual(data["reviewers_ok"], 3)
        self.assertEqual(data["lone_blocking"], [])
        self.assertFalse(data["infra"])

    def test_classify_flags_lone_blocking(self):
        out = subprocess.run([sys.executable, MERGE, "--phase", "classify",
                              *fx("v_lone_bug.json", "v_claude_clean.json"),
                              "--block-at", "1"], capture_output=True, text=True)
        data = json.loads(out.stdout)
        self.assertEqual(len(data["lone_blocking"]), 1)

    def test_classify_infra_when_fewer_than_two(self):
        out = subprocess.run([sys.executable, MERGE, "--phase", "classify",
                              *fx("v_codex_bug.json"), "--block-at", "1"], capture_output=True, text=True)
        data = json.loads(out.stdout)
        self.assertTrue(data["infra"])

    def test_strict_reports_no_lone_to_challenge(self):
        out = subprocess.run([sys.executable, MERGE, "--phase", "classify", "--strict",
                              *fx("v_lone_bug.json", "v_claude_clean.json"),
                              "--block-at", "1"], capture_output=True, text=True)
        data = json.loads(out.stdout)
        self.assertEqual(data["lone_blocking"], [])  # strict: nothing gets challenged

class TestFuzzyDedup(unittest.TestCase):
    def test_overlapping_line_ranges_merge_same_bug(self):
        # The real-panel case: one bug flagged by 3 models at DIFFERENT line refs
        # (3, 2-5, 4). Exact-string dedup left these as 3 lone findings; fuzzy dedup
        # (same file + overlapping ranges, chained via union-find) must merge to one
        # agreement=3 finding so consensus is scored correctly.
        vs = [merge.load_verdict(p) for p in
              fx("v_auth_codex.json", "v_auth_gemini.json", "v_auth_claude.json")]
        merged = merge.dedup(vs)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["agreement"], 3)
        self.assertEqual(merged[0]["priority"], 0)

    def test_distinct_nonoverlapping_ranges_stay_separate(self):
        # Two genuinely different bugs in the same file, non-overlapping ranges
        # (9-11 vs 14) must NOT over-merge.
        vs = [merge.load_verdict(p) for p in fx("v_distinct_a.json", "v_distinct_b.json")]
        merged = merge.dedup(vs)
        self.assertEqual(len(merged), 2)
        self.assertTrue(all(f["agreement"] == 1 for f in merged))

    def test_basename_match_merges_across_path_depth(self):
        # Same bug, one model cites src/db.py:42, another db.py:42 → basenames match.
        vs = [merge.load_verdict(p) for p in fx("v_codex_bug.json", "v_basename_short.json")]
        merged = merge.dedup(vs)
        self.assertEqual(len(merged), 1)
        self.assertEqual(merged[0]["agreement"], 2)

    def test_fuzzy_dedup_order_independent(self):
        a = merge.dedup([merge.load_verdict(p) for p in
                         fx("v_auth_codex.json", "v_auth_gemini.json", "v_auth_claude.json")])
        b = merge.dedup([merge.load_verdict(p) for p in
                         fx("v_auth_claude.json", "v_auth_codex.json", "v_auth_gemini.json")])
        self.assertEqual({merge.finding_key(f) for f in a},
                         {merge.finding_key(f) for f in b})

class TestFinalize(unittest.TestCase):
    def _run(self, verdicts, challenge=None, block_at="1", strict=False):
        cmd = [sys.executable, MERGE, "--phase", "finalize", *fx(*verdicts), "--block-at", block_at]
        if strict: cmd.append("--strict")
        if challenge: cmd += ["--challenge", *fx(*challenge)]
        p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode, json.loads(p.stdout)

    def test_all_clean_exit_0(self):
        rc, data = self._run(["v_claude_clean.json", "v_claude_clean.json"])
        self.assertEqual(rc, 0)
        self.assertTrue(data["_gate"]["clean"])

    def test_corroborated_blocks_exit_1(self):
        rc, data = self._run(["v_codex_bug.json", "v_gemini_bug.json", "v_claude_clean.json"])
        self.assertEqual(rc, 1)
        self.assertEqual(data["_gate"]["blocking_count"], 1)

    def test_infra_fewer_than_two_exit_2(self):
        rc, data = self._run(["v_codex_bug.json"])
        self.assertEqual(rc, 2)
        self.assertFalse(data["_gate"]["clean"])

    def test_lone_block_confirmed_stays_blocking(self):
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"],
                             challenge=["challenge_confirm.json"])
        self.assertEqual(rc, 1)
        f = data["findings"][0]
        self.assertEqual(f["challenge"], "confirmed")

    def test_lone_block_refuted_demoted_exit_0(self):
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"],
                             challenge=["challenge_refute.json"])
        self.assertEqual(rc, 0)
        f = data["findings"][0]
        self.assertEqual(f["challenge"], "refuted")
        self.assertGreater(f["priority"], 1)  # demoted below block_at
        self.assertTrue(any(d for d in data["_panel"]["disagreements"]))

    def test_mixed_confirm_and_refute_stays_blocking(self):
        # A confirmation from any challenger overrides a refutation: stays blocking.
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"],
                             challenge=["challenge_confirm.json", "challenge_refute.json"])
        self.assertEqual(rc, 1)
        f = data["findings"][0]
        self.assertEqual(f["challenge"], "confirmed")

    def test_refuted_demotion_is_relative_to_block_at(self):
        # With --block-at 2, a refuted finding must demote ABOVE 2, not to a
        # hardcoded 2 (which would still satisfy 2<=2 and keep blocking).
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"],
                             challenge=["challenge_refute.json"], block_at="2")
        self.assertEqual(rc, 0)
        f = data["findings"][0]
        self.assertGreater(f["priority"], 2)

    def test_lone_block_no_challenge_result_stays_blocking(self):
        # challenge round produced nothing (infra failure) → conservative: stays blocking
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"])
        self.assertEqual(rc, 1)

    def test_strict_lone_block_blocks_without_challenge(self):
        rc, data = self._run(["v_lone_bug.json", "v_claude_clean.json"], strict=True)
        self.assertEqual(rc, 1)

if __name__ == "__main__":
    unittest.main()
