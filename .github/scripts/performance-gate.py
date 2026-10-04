#!/usr/bin/env python3
"""Validate named AndroidX Macrobenchmark metrics. Never infer metrics from arbitrary numbers."""
import argparse
import json
import math
import sys
from pathlib import Path


class InvalidEvidence(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidEvidence(message)


def number(value, label, minimum=None):
    require(type(value) in (int, float), f"Invalid number: {label}")
    try:
        value = float(value)
    except OverflowError as error:
        raise InvalidEvidence(f"Invalid number: {label}") from error
    require(math.isfinite(value), f"Non-finite number: {label}")
    if minimum is not None:
        require(value >= minimum, f"Out-of-range number: {label}")
    return float(value)


def percentile(values, p):
    values = sorted(values)
    index = (len(values) - 1) * p
    lower, upper = math.floor(index), math.ceil(index)
    return values[lower] + (values[upper] - values[lower]) * (index - lower)


def read_json(path):
    def unique_pairs(pairs):
        obj = {}
        for key, value in pairs:
            require(key not in obj, f"Duplicate JSON key: {key}")
            obj[key] = value
        return obj
    with Path(path).open(encoding="utf-8") as handle:
        return json.load(handle, object_pairs_hook=unique_pairs)


def evaluate(documents, policy, mode, device_fingerprint=None):
    require(mode in ("diagnostic", "enforce"), "Unknown execution mode")
    require(isinstance(policy, dict) and policy.get("schemaVersion") == 1, "Unsupported policy")
    require(isinstance(policy.get("scope"), str) and policy["scope"], "Policy scope required")
    requirements = policy.get("requirements")
    require(isinstance(requirements, list) and requirements, "Empty metric policy")
    require(documents, "No benchmark reports supplied")
    records, contexts = {}, []
    for document in documents:
        require(isinstance(document, dict), "Benchmark report must be an object")
        context = document.get("context")
        benchmarks = document.get("benchmarks")
        require(isinstance(context, dict), "Missing benchmark context")
        build = context.get("build")
        require(isinstance(build, dict), "Missing device build information")
        fingerprint = build.get("fingerprint")
        require(isinstance(fingerprint, str) and fingerprint, "Missing build fingerprint")
        if mode == "enforce":
            require(device_fingerprint and fingerprint == device_fingerprint,
                    "Enforcement requires an explicitly approved, matching device fingerprint")
            emulator_markers = ("generic", "emulator", "sdk_gphone", "ranchu", "goldfish")
            identity = " ".join(str(build.get(k, "")) for k in ("fingerprint", "model", "device")).lower()
            require(not any(marker in identity for marker in emulator_markers),
                    "Emulator results cannot be enforced as physical-device measurements")
        require(isinstance(benchmarks, list) and benchmarks, "Empty or missing benchmarks")
        contexts.append(context)
        for benchmark in benchmarks:
            require(isinstance(benchmark, dict), "Invalid benchmark record")
            key = (benchmark.get("className"), benchmark.get("name"))
            require(all(isinstance(v, str) and v for v in key), "Unnamed benchmark")
            require(key not in records, f"Duplicate benchmark result: {key}")
            records[key] = benchmark
    require(all(context == contexts[0] for context in contexts), "Mixed device/run contexts")

    measured, seen = [], set()
    for requirement in requirements:
        require(isinstance(requirement, dict), "Invalid metric requirement")
        key = (requirement.get("className"), requirement.get("test"))
        require(all(isinstance(v, str) and v for v in key), "Invalid test selector")
        require(key in records, f"Required benchmark missing: {key}")
        metric = requirement.get("metric")
        # Explicit units and semantics; unsupported/new metrics require a reviewed extension.
        kinds = {
            "timeToInitialDisplayMs": "metrics",
            "timeToFullDisplayMs": "metrics",
            "frameDurationCpuMs": "sampledMetrics",
            "frameOverrunMs": "sampledMetrics",
        }
        require(isinstance(metric, str) and metric in kinds, f"Unsupported metric: {metric}")
        statistic = requirement.get("statistic")
        require(statistic in ("median", "P50", "P90", "P95", "P99"), "Unsupported statistic")
        identity = (*key, metric, statistic)
        require(identity not in seen, f"Duplicate policy requirement: {identity}")
        seen.add(identity)
        minimum = requirement.get("minIterations")
        require(type(minimum) is int and minimum >= 2, "minIterations must be an integer >= 2")
        warning = number(requirement.get("warningMs"), "warningMs")
        failure = number(requirement.get("failureMs"), "failureMs")
        require(warning < failure, "warningMs must be less than failureMs")
        record = records[key]
        container = record.get(kinds[metric])
        require(isinstance(container, dict), f"Missing {kinds[metric]} for {key}")
        payload = container.get(metric)
        require(isinstance(payload, dict), f"Missing metric {metric} for {key}")
        runs = payload.get("runs")
        require(isinstance(runs, list) and len(runs) >= minimum, f"Insufficient iterations: {identity}")
        values = []
        for run in runs:
            samples = run if kinds[metric] == "sampledMetrics" else [run]
            require(isinstance(samples, list) and samples, f"Empty/malformed sample iteration: {identity}")
            for sample in samples:
                value = number(sample, metric, None if metric == "frameOverrunMs" else 0)
                if metric.startswith("timeTo"):
                    require(value > 0, "Startup timing must be positive")
                values.append(value)
        p = 0.5 if statistic == "median" else int(statistic[1:]) / 100
        value = percentile(values, p)
        verdict = "FAIL" if value >= failure else "WARNING" if value >= warning else "PASS"
        measured.append({
            "className": key[0], "test": key[1], "metric": metric, "statistic": statistic,
            "valueMs": value, "iterations": len(runs), "samples": len(values),
            "warningMs": warning, "failureMs": failure, "thresholdVerdict": verdict,
        })
    failed = any(item["thresholdVerdict"] == "FAIL" for item in measured)
    warned = any(item["thresholdVerdict"] == "WARNING" for item in measured)
    verdict = "FAIL" if failed else "WARNING" if warned else "PASS"
    return {
        "schemaVersion": 1, "scope": policy["scope"], "mode": mode,
        "status": "DIAGNOSTIC_ONLY" if mode == "diagnostic" else verdict,
        "thresholdVerdict": verdict, "releaseEligible": False,
        "note": "Metric evidence only; does not replace functional, crash, quality or release approval checks.",
        "context": contexts[0], "measurements": measured,
    }, (1 if mode == "enforce" and failed else 0)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--results", nargs="+", type=Path, required=True)
    parser.add_argument("--policy", type=Path, required=True)
    parser.add_argument("--mode", choices=("diagnostic", "enforce"), required=True)
    parser.add_argument("--device-fingerprint", help="Approved physical-device fingerprint (enforce only)")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        require(len(set(path.resolve() for path in args.results)) == len(args.results), "Duplicate report paths")
        result, code = evaluate([read_json(path) for path in args.results], read_json(args.policy),
                                args.mode, args.device_fingerprint)
    except (InvalidEvidence, OSError, ValueError) as error:
        result, code = {"status": "INVALID_EVIDENCE", "releaseEligible": False, "error": str(error)}, 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n")
    print(json.dumps(result, ensure_ascii=False, allow_nan=False))
    return code


if __name__ == "__main__":
    sys.exit(main())
