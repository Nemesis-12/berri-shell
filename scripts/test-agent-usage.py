"""Usage readings keep percentages and recover from failed requests."""
import importlib.util
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("agent_usage", Path(__file__).with_name("agent-usage.py"))
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


class PercentageTests(unittest.TestCase):
    def test_usage_percentage_keeps_small_values(self):
        reset = "2030-01-01T00:00:00Z"
        for percent in (0, 0.5, 1, 1.1, 100):
            with self.subTest(percent=percent):
                self.assertEqual(usage.claude_bucket({"utilization": percent, "resets_at": reset}),
                                 {"percent": percent, "resetsAt": reset})
                self.assertEqual(usage.codex_window({"usedPercent": percent, "resetsAt": 1893456000}),
                                 {"percent": percent, "resetsAt": "2030-01-01T00:00:00+00:00"})


if __name__ == "__main__":
    unittest.main()
