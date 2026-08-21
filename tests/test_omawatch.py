import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import omawatch


class MoodMappingTests(unittest.TestCase):
    def test_drained_state_maps_to_safe_unwind(self):
        mood = omawatch._mood_from_answers({"state": "drained"})
        self.assertEqual(mood["energy"], "unwind")
        self.assertEqual(mood["risk"], "safe")

    def test_horror_appetite_sets_tone_and_trust(self):
        mood = omawatch._mood_from_answers({"appetite": "horror"})
        self.assertEqual(mood["tone"], "dark")
        self.assertEqual(mood["trust"], "horror")

    def test_comfort_appetite_stays_warm(self):
        mood = omawatch._mood_from_answers({"appetite": "comfort"})
        self.assertEqual(mood["depth"], "warm")
        self.assertEqual(mood["risk"], "safe")

    def test_runtime_tone_depth_and_company_pass_through(self):
        mood = omawatch._mood_from_answers(
            {"runtime": "short", "tone": "light", "depth": "uneasy", "company": "together"}
        )
        self.assertEqual(mood["runtime"], "short")
        self.assertEqual(mood["tone"], "light")
        self.assertEqual(mood["depth"], "uneasy")
        self.assertEqual(mood["company"], "shared")

    def test_unknown_answers_are_ignored(self):
        self.assertEqual(omawatch._mood_from_answers({"state": "???"}), {})


class HelperCliTests(unittest.TestCase):
    def _run(self, command, payload):
        proc = subprocess.run(
            [sys.executable, str(Path(__file__).resolve().parent.parent / "omawatch.py"), command],
            input=json.dumps(payload),
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return json.loads(proc.stdout)

    def test_unknown_command_fails_cleanly(self):
        result = self._run("nope", {})
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "unknown-command")

    def test_sync_start_rejects_invalid_username(self):
        result = self._run("sync-start", {"username": "no valid user!"})
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "invalid-username")

    def test_sync_start_propagates_cached_watchlist_token(self):
        result = self._run("sync-start", {"username": "brm"})
        self.assertTrue(result["ok"], result)
        self.assertIn(result.get("status"), ("ready", "ready_partial", "queued"))
        if result.get("status") in ("ready", "ready_partial"):
            self.assertTrue(result.get("watchlist_token"))

    def test_recommend_rejects_empty_watchlist_token(self):
        result = self._run("recommend-wl", {"answers": {}})
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "watchlist-token-missing")

    def test_sync_status_requires_token(self):
        result = self._run("sync-status", {})
        self.assertFalse(result["ok"])
        self.assertEqual(result["error"], "sync-token-missing")

    def test_helper_answers_after_separator_without_stdin_eof(self):
        import select

        proc = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve().parent.parent / "omawatch.py")],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
        )
        assert proc.stdin is not None
        assert proc.stdout is not None
        proc.stdin.write(b'{"username":"bad user"}\x1e')
        proc.stdin.flush()
        ready, _, _ = select.select([proc.stdout], [], [], 3)
        self.assertTrue(ready, "helper waited for EOF instead of the record separator")
        result = json.loads(proc.stdout.readline())
        proc.kill()
        proc.wait(timeout=3)
        proc.stdin.close()
        proc.stdout.close()
        self.assertEqual(result["error"], "unknown-command")

    def test_recommend_returns_films(self):
        result = self._run(
            "recommend",
            {
                "lang": "es",
                "country": "CL",
                "answers": {"state": "restless", "appetite": "horror", "tone": "dark"},
                "seed": 11,
            },
        )
        self.assertTrue(result["ok"], result)
        self.assertTrue(len(result["films"]) >= 1)
        self.assertIn("title", result["films"][0])


if __name__ == "__main__":
    unittest.main()
