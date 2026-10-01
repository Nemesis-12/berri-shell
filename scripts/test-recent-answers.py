"""Tests for recent answer reads, writes and age limits."""
import os
import tempfile
import time
import unittest
from pathlib import Path

from recent_answers import answer_path, read_recent_answer, save_answer


class RecentAnswerTests(unittest.TestCase):
    def test_answer_round_trip_and_age(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "berri-shell" / "data.json"
            self.assertIsNone(read_recent_answer(path))
            text = '{"count": 3}\n'
            save_answer(path, text)
            self.assertEqual(read_recent_answer(path, 60), text)
            old = time.time() - 120
            os.utime(path, (old, old))
            self.assertIsNone(read_recent_answer(path, 60))
            self.assertEqual(read_recent_answer(path), text)

    def test_answer_path_uses_cache_home(self):
        from unittest.mock import patch
        with patch.dict(os.environ, {"XDG_CACHE_HOME": "/tmp/script-test-cache"}):
            self.assertEqual(answer_path("data.json"), Path("/tmp/script-test-cache/berri-shell/data.json"))


if __name__ == "__main__":
    unittest.main()
