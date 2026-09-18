#!/usr/bin/env python3
"""Summarize PerformanceMonitor JSON snapshots from an Android run."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Any


def number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def cycle_from_label(label: str) -> str:
    if label == "cold_start_after":
        return "0"
    match = re.search(r"cycle_(\d+)", label)
    return match.group(1) if match else ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--raw-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_csv = args.output_dir / "frame_metrics.csv"
    output_summary = args.output_dir / "frame_summary.txt"
    files = sorted(args.raw_dir.glob("*_performance.json"))

    fields = [
        "label",
        "cycle",
        "report_timestamp",
        "total_frames",
        "jank_frames",
        "frame_delta",
        "jank_delta",
        "average_frame_time_ms",
        "average_build_time_ms",
        "average_raster_time_ms",
        "max_build_time_ms",
        "max_raster_time_ms",
        "current_fps",
        "peak_memory_mb",
        "total_rebuilds",
        "performance_score",
    ]

    rows: list[dict[str, object]] = []
    previous_frames = 0
    previous_jank = 0
    for path in files:
        try:
            report = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue

        label = re.sub(r"^\d+_", "", path.stem)
        label = re.sub(r"_performance$", "", label)
        fps = report.get("fps") or {}
        memory = report.get("memory") or {}
        rebuilds = report.get("rebuilds") or {}
        total_frames = int(number(fps.get("totalFrames")))
        jank_frames = int(number(fps.get("jankFrames")))
        restarted = total_frames < previous_frames or jank_frames < previous_jank
        frame_delta = total_frames if restarted else max(0, total_frames - previous_frames)
        jank_delta = jank_frames if restarted else max(0, jank_frames - previous_jank)
        rows.append(
            {
                "label": label,
                "cycle": cycle_from_label(label),
                "report_timestamp": report.get("timestamp", ""),
                "total_frames": total_frames,
                "jank_frames": jank_frames,
                "frame_delta": frame_delta,
                "jank_delta": jank_delta,
                "average_frame_time_ms": f"{number(fps.get('averageFrameTimeMs')):.2f}",
                "average_build_time_ms": f"{number(fps.get('averageBuildTimeMs')):.2f}",
                "average_raster_time_ms": f"{number(fps.get('averageRasterTimeMs')):.2f}",
                "max_build_time_ms": f"{number(fps.get('maxBuildTimeMs')):.2f}",
                "max_raster_time_ms": f"{number(fps.get('maxRasterTimeMs')):.2f}",
                "current_fps": f"{number(fps.get('current')):.2f}",
                "peak_memory_mb": f"{number(memory.get('peakMB')):.2f}",
                "total_rebuilds": int(number(rebuilds.get("total"))),
                "performance_score": number(report.get("score")),
            }
        )
        previous_frames = total_frames
        previous_jank = jank_frames

    with output_csv.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    if not rows:
        output_summary.write_text(
            "status=NO_PROFILE_REPORT\n"
            "message=No PerformanceMonitor JSON snapshots were produced.\n",
            encoding="utf-8",
        )
        print("PROFILE_PERFORMANCE status=NO_PROFILE_REPORT")
        return 0

    frame_deltas = [int(row["frame_delta"]) for row in rows]
    jank_deltas = [int(row["jank_delta"]) for row in rows]
    frame_times = [float(row["average_frame_time_ms"]) for row in rows]
    build_times = [float(row["average_build_time_ms"]) for row in rows]
    raster_times = [float(row["average_raster_time_ms"]) for row in rows]
    fps_values = [float(row["current_fps"]) for row in rows if float(row["current_fps"]) > 0]
    max_jank = max(jank_deltas, default=0)
    total_frame_delta = sum(frame_deltas)
    total_jank_delta = sum(jank_deltas)
    jank_ratio = total_jank_delta / total_frame_delta if total_frame_delta else 0.0

    summary = (
        "status=PASS\n"
        f"snapshot_count={len(rows)}\n"
        f"total_frame_delta={total_frame_delta}\n"
        f"total_jank_delta={total_jank_delta}\n"
        f"jank_ratio={jank_ratio:.4f}\n"
        f"max_jank_delta_per_snapshot={max_jank}\n"
        f"average_frame_time_ms={sum(frame_times) / len(frame_times):.2f}\n"
        f"average_build_time_ms={sum(build_times) / len(build_times):.2f}\n"
        f"average_raster_time_ms={sum(raster_times) / len(raster_times):.2f}\n"
        f"minimum_reported_fps={min(fps_values, default=0):.2f}\n"
    )
    output_summary.write_text(summary, encoding="utf-8")
    print("PROFILE_PERFORMANCE " + summary.replace("\n", " ").strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
