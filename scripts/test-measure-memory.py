"""Memory accounting uses kernel units and DRM client identities."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "memory", Path(__file__).resolve().parents[1] / "tools/measure-memory.py")
memory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(memory)


class MemoryTests(unittest.TestCase):
    def test_smaps_reports_rss_pss_and_anon_in_kib(self):
        self.assertEqual(memory.parse_smaps(
            "Rss: 4096 kB\nPss: 3072 kB\nPss_Anon: 2048 kB\nPss_File: 1024 kB\n"),
            {"RSS": 4096, "PSS": 3072, "anon": 2048})

    def test_gpu_counts_clients_once_not_equal_memory_values(self):
        client = "drm-pdev: 0000:03:00.0\ndrm-client-id: 4\ndrm-memory-vram: 1024 KiB\ndrm-memory-gtt: 2097152 B\n"
        other = client.replace("id: 4", "id: 5")
        device = client.replace("03:00", "04:00")
        self.assertEqual(memory.parse_gpu([client, client, other, device, "pos: 0\n"]),
                         {"VRAM": 3072, "GTT": 6144})

    def test_missing_gpu_or_cpu_counters_cannot_be_reported_as_zero(self):
        with self.assertRaises(ValueError):
            memory.parse_gpu(["pos: 0\n"])
        with self.assertRaises(KeyError):
            memory.parse_smaps("Rss: 4096 kB\n")

    def test_exact_config_path_excludes_omarchy_and_other_worktrees(self):
        listing = (
            "Instance omarchy:\n  Process ID: 11\n  Config path: /usr/share/omarchy/shell/shell.qml\n\n"
            "Instance other:\n  Process ID: 12\n  Config path: /repo/berri-other/shell.qml\n\n"
            "Instance berri:\n  Process ID: 13\n  Config path: /repo/berri/shell.qml\n")
        self.assertEqual(memory.parse_instance(listing, Path("/repo/berri")), ("berri", 13))
        with self.assertRaises(ValueError):
            memory.parse_instance(listing, Path("/repo/missing"))
        with self.assertRaises(ValueError):
            memory.parse_instance(listing + listing, Path("/repo/berri"))

    def test_gpu_converts_mib_and_rejects_unknown_units(self):
        client = "drm-client-id: 9\ndrm-memory-vram: 2 MiB\ndrm-memory-gtt: 512 kB\n"
        self.assertEqual(memory.parse_gpu([client]), {"VRAM": 2048, "GTT": 512})
        with self.assertRaises(KeyError):
            memory.parse_gpu([client.replace("MiB", "unknown")])

    def test_warm_up_opens_all_tabs_and_both_actual_picker_bodies(self):
        from unittest.mock import patch
        with patch.object(memory.subprocess, "run") as commands, \
                patch.object(memory.time, "sleep") as sleeps:
            memory.warm_views("berri-id")
        self.assertEqual([call.args[0][6:] for call in commands.call_args_list], [
            ("dash", "home"), ("dash", "media"), ("dash", "system"),
            ("dash", "code"), ("dash", "calendar"), ("dash", "weather"),
            ("dash", "alerts"), ("dashClose",), ("open", "themes"),
            ("close",), ("open", "walls"), ("close",)])
        self.assertEqual([call.args[0] for call in sleeps.call_args_list],
                         [2, 2, 2, 2, 2, 2, 2, 1, 3, 1, 3, 1, 20])
