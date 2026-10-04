"""Check hardware sampling with synthetic Linux sysfs files."""
import pathlib
import subprocess
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).with_name("system-hardware.sh")


class SystemHardwareTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (SCRIPT.parent.parent / "scratchpad").mkdir(exist_ok=True)

    # Write a synthetic sysfs value and create its parent folders.
    def write(self, root, name, value):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(value) + "\n")

    # Run the same sampler command that the System services use.
    def sample(self, mode, root):
        return subprocess.run(["sh", str(SCRIPT), mode, str(root)],
                              capture_output=True, text=True, check=True)

    def test_six_cores_need_no_laptop_sensor(self):
        with tempfile.TemporaryDirectory(dir=SCRIPT.parent.parent / "scratchpad") as folder:
            root = pathlib.Path(folder)
            for cpu in range(6):
                base = f"devices/system/cpu/cpu{cpu}"
                self.write(root, base + "/topology/physical_package_id", 0)
                self.write(root, base + "/topology/core_id", cpu)
            sample = self.sample("cores", root)
            self.assertEqual(sorted(sample.stdout.splitlines()),
                             [f"{cpu} 0 {cpu}" for cpu in range(6)])
            sensors = self.sample("sensors", root)
            self.assertEqual(sensors.stdout, "")
            self.assertEqual(sensors.stderr, "")

    def test_frequency_includes_online_cpus_and_skips_missing_files(self):
        with tempfile.TemporaryDirectory(dir=SCRIPT.parent.parent / "scratchpad") as folder:
            root = pathlib.Path(folder)
            for cpu in range(16):
                self.write(root, f"devices/system/cpu/cpu{cpu}/cpufreq/scaling_cur_freq",
                           2000000 if cpu < 8 else 4000000)
            self.write(root, "devices/system/cpu/cpu16/online", 0)
            self.write(root, "devices/system/cpu/cpu16/cpufreq/scaling_cur_freq", 99000000)
            self.write(root, "devices/system/cpu/cpu18/online", 1)
            sample = self.sample("frequency", root)
            self.assertEqual(sorted(sample.stdout.splitlines()), ["2000000"] * 8 + ["4000000"] * 8)
            self.assertEqual(sample.stderr, "")

    def test_sensor_probe_emits_only_existing_inputs_and_labels(self):
        with tempfile.TemporaryDirectory(dir=SCRIPT.parent.parent / "scratchpad") as folder:
            root = pathlib.Path(folder)
            self.write(root, "class/hwmon/hwmon0/name", "coretemp")
            self.write(root, "class/hwmon/hwmon0/temp2_input", 54000)
            self.write(root, "class/hwmon/hwmon0/temp2_label", "Package id 0")
            self.write(root, "class/hwmon/hwmon1/name", "asus")
            self.write(root, "class/hwmon/hwmon1/fan2_input", 0)
            sample = self.sample("sensors", root)
            self.assertEqual(sample.stdout,
                             f"S\tcoretemp\t{root}/class/hwmon/hwmon0/temp2_input\tPackage id 0\n"
                             f"S\tasus\t{root}/class/hwmon/hwmon1/fan2_input\t\n")
            self.assertEqual(sample.stderr, "")


if __name__ == "__main__":
    unittest.main()
