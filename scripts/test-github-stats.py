"""Historical contribution years refresh when the caller forces a read."""
import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("github_stats", Path(__file__).with_name("github-stats.py"))
stats = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stats)


class HistoricalYearTests(unittest.TestCase):
    def test_force_refresh_replaces_a_cached_finished_year(self):
        cached = {2025: {"year": 2025, "total": 1, "days": [], "final": True}}
        response = {"data": {"viewer": {"y2025": {"contributionCalendar": {
            "totalContributions": 99, "weeks": [],
        }}}}}
        with patch.object(stats, "gh", return_value=response) as request:
            years = stats.fetch_years([2025], cached, force=True)
        self.assertEqual(years[0]["total"], 99)
        request.assert_called_once()


if __name__ == "__main__":
    unittest.main()
