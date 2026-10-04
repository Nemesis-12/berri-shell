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

    def test_partial_copies_do_not_replace_final_usage_or_merge_distinct_responses(self):
        scratch = Path(__file__).resolve().parent.parent / "scratchpad"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            final = Path(folder) / "final.jsonl"
            copied = Path(folder) / "copied.jsonl"
            final.write_text(json.dumps(response()) + "\n", encoding="utf-8")
            copied.write_text("\n".join(json.dumps(message) for message in (
                response(output=2), response("new-response", output=5),
            )) + "\n", encoding="utf-8")
            expected = [34, 19]
            for paths in ([final, copied], [copied, final]):
                readings = list(stats.claude_events(paths, dt.date.today()))
                self.assertEqual(sorted(stats.counted(kinds) for _, _, kinds in readings), sorted(expected))
                self.assertEqual(sum(stats.counted(kinds) for _, _, kinds in readings), 53)

    def test_codex_running_totals_are_independent_for_each_session(self):
        scratch = Path(__file__).resolve().parent.parent / "scratchpad"
        scratch.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as folder:
            root = Path(folder) / ".codex" / "sessions"
            root.mkdir(parents=True)
            timestamp = dt.datetime.now().astimezone().isoformat()
            turn = {"type": "turn_context", "payload": {"model": "gpt-test"}}
            total = {"timestamp": timestamp, "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 80, "output_tokens": 5},
            }}}
            increased = {"timestamp": timestamp, "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 110, "cached_input_tokens": 80, "output_tokens": 7},
            }}}
            for name in ("first", "second"):
                (root / f"{name}.jsonl").write_text("\n".join(json.dumps(event) for event in (
                    turn, total, total, increased,
                )) + "\n", encoding="utf-8")
            with patch.object(Path, "home", return_value=Path(folder)), \
                 patch.object(stats, "load_prices", return_value=({}, {})):
                result = stats.collect()
            self.assertEqual(result["usage"]["codex"], {
                period: {"tokens": 74, "cost": 0.0} for period in ("today", "week", "month")
            })
            self.assertEqual(result["models"]["codex"], [{"name": "GPT-Test", "tokens": 74}])
            self.assertEqual(result["unpricedModels"]["codex"], ["gpt-test"])


if __name__ == "__main__":
    unittest.main()
