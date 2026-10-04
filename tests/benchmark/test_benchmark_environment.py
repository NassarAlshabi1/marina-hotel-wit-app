"""Synthetic RAM fixtures, not measurements of Android hardware."""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[2] / '.github/scripts/benchmark-environment.py'
spec = importlib.util.spec_from_file_location('benchmark_environment', SCRIPT)
environment = importlib.util.module_from_spec(spec)
spec.loader.exec_module(environment)


class BenchmarkEnvironmentTest(unittest.TestCase):
    def test_reserved_memory_window_boundaries(self):
        for mib in (768, 900, 1024):
            with self.subTest(mib=mib):
                result = environment.validate(f'MemTotal: {mib * 1024} kB\r\n')
                self.assertEqual('RAM_PREFLIGHT_ONLY', result['status'])
                self.assertFalse(result['releaseEligible'])

    def test_rejects_wrong_profile_including_observed_oversize(self):
        for kib in (0, 768 * 1024 - 1, 1024 * 1024 + 1, 2534548):
            with self.subTest(kib=kib), self.assertRaises(ValueError):
                environment.validate(f'MemTotal: {kib} kB')

    def test_rejects_missing_duplicate_and_malformed_memory(self):
        for text in ('', 'MemFree: 921600 kB', 'MemTotal: -1 kB',
                     'MemTotal: 900 MB', 'MemTotal: 921600.0 kB',
                     'MemTotal: 921600 kB\nMemTotal: 921600 kB'):
            with self.subTest(text=text), self.assertRaises(ValueError):
                environment.validate(text)

    def test_context_must_be_a_positive_integer_not_boolean_or_float(self):
        for value in (None, True, 0, -1, '943718400', 943718400.0):
            with self.subTest(value=value), self.assertRaises(ValueError):
                environment.validate('MemTotal: 921600 kB', {'context': {'memTotalBytes': value}})

    def test_agreeing_sources_are_not_release_approval(self):
        result = environment.validate('MemTotal: 921600 kB', {'context': {'memTotalBytes': 943718400}})
        self.assertEqual('RAM_VERIFIED_ONLY', result['status'])
        self.assertFalse(result['releaseEligible'])

    def test_context_tolerance_is_bounded(self):
        environment.validate('MemTotal: 921600 kB', {'context': {'memTotalBytes': 943718400 + 1024**2}})
        with self.assertRaises(ValueError):
            environment.validate('MemTotal: 921600 kB', {'context': {'memTotalBytes': 943718400 + 1024**2 + 1}})

    def test_missing_or_wrong_context_is_rejected(self):
        for summary in ([], {}, {'context': None}, {'context': {'memTotalBytes': 2595377152}}):
            with self.subTest(summary=summary), self.assertRaises(ValueError):
                environment.validate('MemTotal: 921600 kB', summary)

    def test_cli_writes_failure_for_invalid_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            meminfo, summary, output = (root / name for name in ('meminfo', 'summary', 'output'))
            meminfo.write_text('MemTotal: 921600 kB')
            for text in ('null', '{', '{}'):
                summary.write_text(text)
                result = subprocess.run([sys.executable, str(SCRIPT), '--meminfo', str(meminfo),
                                         '--summary', str(summary), '--output', str(output)],
                                        capture_output=True, text=True)
                self.assertEqual(2, result.returncode)
                self.assertEqual('INVALID_ENVIRONMENT', json.loads(output.read_text())['status'])
