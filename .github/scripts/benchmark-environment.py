#!/usr/bin/env python3
"""Validate the fixed 1024-MiB emulator profile, not physical-device suitability."""
import argparse
import json
import re
from pathlib import Path

REQUESTED_MIB = 1024
# MemTotal excludes reserved kernel/device memory. This window is a profile
# acceptance criterion, not a claim that usable memory equals installed RAM.
MIN_USABLE_MIB = 768
MAX_CONTEXT_DIFFERENCE_BYTES = 1024 * 1024


def validate(meminfo, summary=None):
    entries = [line for line in meminfo.splitlines() if line.lstrip().startswith("MemTotal:")]
    if len(entries) != 1:
        raise ValueError("Exactly one MemTotal entry is required")
    match = re.fullmatch(r"\s*MemTotal:\s*([0-9]+)\s+kB\s*", entries[0])
    if not match:
        raise ValueError("Malformed MemTotal; expected integer kB")
    actual = int(match[1]) * 1024
    if not MIN_USABLE_MIB * 1024**2 <= actual <= REQUESTED_MIB * 1024**2:
        raise ValueError(f"Usable RAM {actual} bytes is outside the 768..1024 MiB profile")
    result = {
        "status": "RAM_PREFLIGHT_ONLY", "releaseEligible": False,
        "requestedRamMiB": REQUESTED_MIB, "minimumUsableRamMiB": MIN_USABLE_MIB,
        "procMemTotalBytes": actual,
    }
    if summary is not None:
        if not isinstance(summary, dict) or not isinstance(summary.get("context"), dict):
            raise ValueError("Benchmark context is missing")
        reported = summary["context"].get("memTotalBytes")
        if type(reported) is not int or reported <= 0:
            raise ValueError("AndroidX memTotalBytes must be a positive integer")
        if not MIN_USABLE_MIB * 1024**2 <= reported <= REQUESTED_MIB * 1024**2:
            raise ValueError("AndroidX RAM is outside the 768..1024 MiB profile")
        if abs(reported - actual) > MAX_CONTEXT_DIFFERENCE_BYTES:
            raise ValueError("AndroidX and /proc/meminfo disagree by more than 1 MiB")
        result.update(status="RAM_VERIFIED_ONLY", androidXMemTotalBytes=reported)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--meminfo", type=Path, required=True)
    parser.add_argument("--summary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        summary = json.loads(args.summary.read_text()) if args.summary else None
        if args.summary and summary is None:
            raise ValueError("Benchmark summary is null")
        result = validate(args.meminfo.read_text(), summary)
        code = 0
    except (OSError, ValueError) as error:
        result = {"status": "INVALID_ENVIRONMENT", "releaseEligible": False, "error": str(error)}
        code = 2
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    text = json.dumps(result).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    level = "error" if code else "notice"
    print(f"::{level} title=Benchmark RAM verification::{text}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
