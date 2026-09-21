"""Runtime CLI checks; temporarily connects eight small virtual displays."""
import pathlib
import re
import signal
import subprocess
import time
import unittest

BINARY = pathlib.Path(__file__).resolve().parents[1] / "build/virtual-second-monitor"


def online_ids():
    output = subprocess.check_output([str(BINARY), "--list"], text=True)
    return {int(value) for value in re.findall(r"id=(\d+)", output)}


class CLITests(unittest.TestCase):
    def test_invalid_arguments(self):
        for args in (["--count", "0"], ["--count", "9"], ["--count", "-1"],
                     ["--count", "1.5"], ["--count"], ["--refresh", "nan"],
                     ["--refresh", "inf"], ["--count", "8", "--serial", "4294967295"]):
            with self.subTest(args=args):
                result = subprocess.run([str(BINARY), *args], capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 2)

    def test_eight_displays_and_signal_cleanup(self):
        before = online_ids()
        process = subprocess.Popen(
            [str(BINARY), "--count", "8", "--width", "640", "--height", "480",
             "--name", "VSM CLI Test"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        connected = set()
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline:
                connected = online_ids() - before
                if len(connected) == 8 or process.poll() is not None:
                    break
                time.sleep(0.1)
            self.assertEqual(len(connected), 8)
        finally:
            process.send_signal(signal.SIGTERM)
            output, error = process.communicate(timeout=15)
        self.assertEqual(process.returncode, 0, error)
        created = re.findall(r"Created virtual monitor \d+: id=(\d+).*serial=(\d+)", output)
        self.assertEqual({int(item[0]) for item in created}, connected)
        self.assertEqual(len({item[1] for item in created}), 8)
        deadline = time.monotonic() + 10
        while connected & online_ids() and time.monotonic() < deadline:
            time.sleep(0.1)
        self.assertFalse(connected & online_ids())
        self.assertTrue(before <= online_ids())


if __name__ == "__main__":
    unittest.main()
