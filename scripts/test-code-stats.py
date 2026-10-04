"""Token totals count one response across copied session histories."""
import datetime as dt
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("code_stats", Path(__file__).with_name("code-stats.py"))
stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stats)


# Write only synthetic IDs, timestamps, model names, and usage counts.
def response(message_id="shared-response", output=20):
    return {
        "type": "assistant", "uuid": "synthetic-line", "timestamp": dt.datetime.now().astimezone().isoformat(),
        "message": {"id": message_id, "model": "claude-sonnet-test", "usage": {
            "input_tokens": 10, "output_tokens": output, "cache_creation_input_tokens": 4,
            "cache_creation": {"ephemeral_5m_input_tokens": 3, "ephemeral_1h_input_tokens": 1},
            "cache_read_input_tokens": 100,
        }},
    }


class CollectedUsageTests(unittest.TestCase):
    def test_shared_response_counts_once_across_session_logs(self):
        scratch = Path(__file__).resolve().parent.parent / "scratchpad"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            root = Path(folder) / ".claude" / "projects" / "synthetic-project"
            root.mkdir(parents=True)
            message = response()
            (root / "original.jsonl").write_text(json.dumps(message) + "\n", encoding="utf-8")
            prices = {"claude-sonnet-test": {
                "input": 10, "output": 20, "cache_write_5m": 10, "cache_write_1h": 20, "cache_read": 0.5,
            }}
            with patch.object(Path, "home", return_value=Path(folder)), \
                 patch.object(stats, "load_prices", return_value=(prices, {})):
                original = stats.collect()
                (root / "resumed.jsonl").write_text(json.dumps(message) + "\n", encoding="utf-8")
                resumed = stats.collect()
            self.assertEqual(original["usage"]["claude"], {
                period: {"tokens": 34, "cost": 0.0006} for period in ("today", "week", "month")
            })
            for field in ("days", "models", "usage", "unpricedModels"):
                self.assertEqual(resumed[field], original[field], field)
            self.assertEqual(resumed["models"]["claude"], [{"name": "Sonnet Test", "tokens": 34}])
            self.assertEqual(resumed["days"][-1]["claude"], 34)


if __name__ == "__main__":
    unittest.main()
