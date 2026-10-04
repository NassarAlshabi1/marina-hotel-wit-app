"""Synthetic AndroidX-shaped fixtures; never presented as measured app performance."""
import copy
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / ".github/scripts/performance-gate.py"
spec = importlib.util.spec_from_file_location("performance_gate", SCRIPT)
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


def policy(metric="timeToInitialDisplayMs", statistic="median"):
    return {"schemaVersion": 1, "scope": "synthetic-test", "requirements": [{
        "className": "example.Benchmark", "test": "test", "metric": metric,
        "statistic": statistic, "minIterations": 2, "warningMs": 25, "failureMs": 50,
    }]}


def document(values=(10, 20), metric="timeToInitialDisplayMs"):
    return {"context": {"build": {"fingerprint": "approved-device-build", "model": "physical-test-fixture"}},
            "benchmarks": [{"className": "example.Benchmark", "name": "test",
                            "metrics" if metric.startswith("timeTo") else "sampledMetrics": {
                                metric: {"runs": list(values), "median": 0, "P95": 0}}}]}


class PerformanceGateTest(unittest.TestCase):
    def evaluate(self, data, rules=None, mode="enforce", fingerprint="approved-device-build"):
        return gate.evaluate([data], policy() if rules is None else rules, mode, fingerprint)

    def test_rejects_unrelated_numeric_json(self):
        with self.assertRaises(gate.InvalidEvidence):
            self.evaluate({"schemaVersion": 1})

    def test_slow_measurements_really_fail(self):
        result, code = self.evaluate(document((60000, 60000)))
        self.assertEqual(1, code)
        self.assertEqual("FAIL", result["status"])
        self.assertFalse(result["releaseEligible"])

    def test_recomputes_median_instead_of_trusting_summary(self):
        result, code = self.evaluate(document((10, 20)))
        self.assertEqual(15, result["measurements"][0]["valueMs"])
        self.assertEqual(0, code)

    def test_p95_and_p99_use_only_frame_samples(self):
        data = document(([1, 2], [3, 100]), "frameDurationCpuMs")
        data["benchmarks"][0]["totalRunTimeNs"] = 9999999999
        for statistic, expected in (("P95", 85.45), ("P99", 97.09)):
            with self.subTest(statistic=statistic):
                result, code = self.evaluate(data, policy("frameDurationCpuMs", statistic))
                self.assertAlmostEqual(expected, result["measurements"][0]["valueMs"])
                self.assertEqual(1, code)

    def test_boundary_thresholds(self):
        for value, status, code in ((24, "PASS", 0), (25, "WARNING", 0), (49, "WARNING", 0), (50, "FAIL", 1)):
            with self.subTest(value=value):
                result, actual = self.evaluate(document((value, value)))
                self.assertEqual(status, result["status"])
                self.assertEqual(code, actual)

    def test_invalid_numbers_and_sample_shapes(self):
        for values in ([True, 10], [float("nan"), 10], [float("inf"), 10], [-1, 10], [0, 10],
                       ["10", 10], [], [10], [[10], [20]], [10**1000, 10]):
            with self.subTest(values=str(values)[:60]):
                with self.assertRaises(gate.InvalidEvidence):
                    self.evaluate(document(values))
        for values in ([[], [1]], [1, 2], [[False], [1]], [[float("nan")], [1]]):
            with self.assertRaises(gate.InvalidEvidence):
                self.evaluate(document(values, "frameDurationCpuMs"), policy("frameDurationCpuMs", "P95"))

    def test_signed_overrun_is_not_confused_with_cpu_frame_duration(self):
        result, code = self.evaluate(document(([-10], [-5]), "frameOverrunMs"), policy("frameOverrunMs", "P95"))
        self.assertEqual(0, code)
        self.assertLess(result["measurements"][0]["valueMs"], 0)

    def test_every_expected_test_and_metric_is_required(self):
        rules = policy()
        for field, value in (("className", "other"), ("test", "missing"), ("metric", "timeToFullDisplayMs")):
            other = copy.deepcopy(rules)
            other["requirements"][0][field] = value
            with self.assertRaises(gate.InvalidEvidence):
                self.evaluate(document(), other)

    def test_duplicate_results_and_mixed_contexts_are_rejected(self):
        data = document()
        data["benchmarks"].append(copy.deepcopy(data["benchmarks"][0]))
        with self.assertRaises(gate.InvalidEvidence):
            self.evaluate(data)
        other = document()
        other["benchmarks"][0]["name"] = "other"
        other["context"]["build"]["fingerprint"] = "another-build"
        with self.assertRaises(gate.InvalidEvidence):
            gate.evaluate([document(), other], policy(), "diagnostic")

    def test_emulator_is_diagnostic_never_device_pass(self):
        data = document((5000, 5000))
        data["context"]["build"]["model"] = "sdk_gphone64_x86_64"
        result, code = self.evaluate(data, mode="diagnostic")
        self.assertEqual(0, code)
        self.assertEqual("DIAGNOSTIC_ONLY", result["status"])
        self.assertEqual("FAIL", result["thresholdVerdict"])
        self.assertFalse(result["releaseEligible"])
        with self.assertRaises(gate.InvalidEvidence):
            self.evaluate(data)
        with self.assertRaises(gate.InvalidEvidence):
            self.evaluate(document(), fingerprint=None)

    def test_invalid_policy_never_disables_gate(self):
        for field, value in (("minIterations", 0), ("minIterations", True), ("metric", "arbitrary"),
                             ("statistic", "average"), ("failureMs", 1), ("warningMs", "25")):
            rules = policy()
            rules["requirements"][0][field] = value
            with self.assertRaises(gate.InvalidEvidence):
                self.evaluate(document(), rules)
        for rules in ({}, {"schemaVersion": 1, "scope": "test", "requirements": []}):
            with self.assertRaises(gate.InvalidEvidence):
                self.evaluate(document(), rules)

    def test_cli_rejects_missing_malformed_and_duplicate_key_json(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            config, report, output = root / "policy.json", root / "result.json", root / "summary.json"
            config.write_text(json.dumps(policy()))
            command = [sys.executable, str(SCRIPT), "--policy", str(config), "--results", str(report),
                       "--mode", "diagnostic", "--output", str(output)]
            for text in (None, "not JSON", '{"context":{},"context":{}}'):
                if text is not None:
                    report.write_text(text)
                result = subprocess.run(command, capture_output=True, text=True)
                self.assertEqual(2, result.returncode)
                self.assertEqual("INVALID_EVIDENCE", json.loads(output.read_text())["status"])


if __name__ == "__main__":
    unittest.main()
