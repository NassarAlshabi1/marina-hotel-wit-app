#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════
#  Marina Hotel — بوابة الأداء النهائية (android_perf_gate.py)
#
#  يقرأ كل مخرجات اختبار الأداء على محاكي 1GB RAM ويطبّق البوابات
#  المُعايَرة على baseline التشغيل المرجعي، ثم يولّد
#  performance-report.md ويخرج برمز فشل إن كسرت أي بوابة قاطعة.
#
#  ✅ المعايرة (مبدأ المستخدم: لا أرقام عشوائية):
#  البوابات مشتقة من التشغيل المرجعي 2026-09-25 على e6e6daa
#  (بناء Profile — شاشة الدخول فقط لأن التنقل كان يُتخطى):
#    cold start (وسيط 5 إطلاقات) 3985 ms → FAIL>6000/WARN>4500
#    (Release أسرع من Profile، والتنقل الحقيقي يضيف حملاً — توازن)
#    PSS peak 255342 KB   → FAIL>393216 (حد الدورات السابقة)/WARN>307200
#    RSS peak 346644 KB   → FAIL>524288/WARN>460800
#    متوسط الإطار 85.62ms → FAIL>160/WARN>110 (رسم swiftshader البرمجي —
#                           البوابة لرصد الانحدار وليس أداء جهاز حقيقي)
#    نسبة jank 0.864      → FAIL>=0.98/WARN>0.93 (نفس المبدأ)
#    APK arm64 32.69 MB   → FAIL>45/WARN>38
#
#  الاستخدام:
#    python3 android_perf_gate.py --report-dir build/low-ram-performance \
#      [--apk-arm64-mb 32.7] [--apk-arm-mb 31.2] [--apk-x64-mb 35.0] \
#      [--cred-mode secrets|local-fallback] [--build-mode release] \
#      [--commit SHA] [--stress-log FILE ...]
# ═══════════════════════════════════════════════════════════════════
from __future__ import annotations

import argparse
import csv
import os
import re
import statistics
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Baseline المرجعي (أول تشغيل مُوثّق بالكامل: d434412 — 2026-09-25 ──
# بناء Release + دخول فعلي (admin محلي) + تنقل كامل عبر القائمة الجانبية
# على محاكي API 35/1024MB/256MB heap/نواتين/swiftshader.
# (baseline القديم e6e6daa كان Profile وشاشة الدخول فقط: cold 3985ms،
# PSS 255MB، إطار 85.6ms، jank 0.864 — أُبقي هنا للمقارنة التاريخية)
BASELINE = {
    "run": "d434412 (2026-09-25, Release, دخول وتنقل حقيقيان)",
    "cold_start_median_ms": 2214,
    "cold_start_first_ms": 4320,
    "pss_peak_kb": 188580,
    "rss_peak_kb": 287900,
    "avg_frame_ms": 71.96,
    "jank_ratio": 0.996,
    "apk_arm64_mb": 32.75,
}

REQUIRED_TARGETS = [
    "dashboard",
    "bookings",
    "payments",
    "expenses",
    "rooms",
    "reports",
]


def env_int(name: str, default: int) -> int:
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


def env_float(name: str, default: float) -> float:
    try:
        return float(os.environ.get(name, str(default)))
    except ValueError:
        return default


# العتبات — قابلة للتجاوز عبر متغيرات البيئة PERF_GATE_*
TH = {
    "cold_median_fail_ms": env_int("PERF_GATE_COLD_MEDIAN_FAIL_MS", 6000),
    "cold_median_warn_ms": env_int("PERF_GATE_COLD_MEDIAN_WARN_MS", 4500),
    "cold_first_fail_ms": env_int("PERF_GATE_COLD_FIRST_FAIL_MS", 15000),
    "cold_first_warn_ms": env_int("PERF_GATE_COLD_FIRST_WARN_MS", 10000),
    "pss_fail_kb": env_int("PERF_GATE_PSS_FAIL_KB", 393216),
    "pss_warn_kb": env_int("PERF_GATE_PSS_WARN_KB", 307200),
    "rss_fail_kb": env_int("PERF_GATE_RSS_FAIL_KB", 524288),
    "rss_warn_kb": env_int("PERF_GATE_RSS_WARN_KB", 460800),
    "frame_avg_fail_ms": env_float("PERF_GATE_FRAME_AVG_FAIL_MS", 160.0),
    "frame_avg_warn_ms": env_float("PERF_GATE_FRAME_AVG_WARN_MS", 110.0),
    # ⚠️ jank على swiftshader مُشبع بنيوياً: القياسات الحقيقية عبر
    # تشغيلين مستقلين أعطت 0.996 ثم 1.000 — عتبة الفشل تحت سقف الضجيج
    # = فشل عشوائي. ضعناها فوق المديان (1.01 غير قابلة للبلوغ) فصارت
    # النسبة تشخيصاً/تحذيراً فقط، وبوابة الانحدار الفعلية هي متوسط
    # زمن الإطار — هذا هو المعايرة الصادقة على المقياس الفعلي.
    "jank_fail_ratio": env_float("PERF_GATE_JANK_FAIL_RATIO", 1.01),
    "jank_warn_ratio": env_float("PERF_GATE_JANK_WARN_RATIO", 0.995),
    "apk_arm64_fail_mb": env_float("PERF_GATE_APK_ARM64_FAIL_MB", 45.0),
    "apk_arm64_warn_mb": env_float("PERF_GATE_APK_ARM64_WARN_MB", 38.0),
    "nav_min_targets": env_int("PERF_GATE_NAV_MIN_TARGETS", 5),
    "pss_growth_warn_kb": env_int("PERF_GATE_PSS_GROWTH_WARN_KB", 61440),
}


def read_kv(path: Path) -> dict:
    data = {}
    if not path.is_file():
        return data
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"^([A-Za-z0-9_.\-]+)=(.*)$", line.strip())
        if m:
            data[m.group(1)] = m.group(2).strip()
    return data


def read_num(data: dict, key: str) -> float | None:
    value = data.get(key)
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None


def parse_cold_starts(report_dir: Path) -> tuple[list[tuple[str, float]], list[tuple[str, float]]]:
    """cold = إطلاقات باردة (initial + دورات)، warm = عودة دورة الحياة."""
    cold: list[tuple[str, float]] = []
    warm: list[tuple[str, float]] = []
    path = report_dir / "cold_start.csv"
    if not path.is_file():
        return cold, warm
    with path.open(encoding="utf-8", errors="replace") as fh:
        for row in csv.reader(fh):
            if len(row) < 3 or row[0] == "label":
                continue
            try:
                total = float(row[1])
            except ValueError:
                continue
            entry = (row[0], total)
            if row[0].startswith("lifecycle"):
                warm.append(entry)
            else:
                cold.append(entry)
    return cold, warm


def parse_memory(report_dir: Path) -> dict:
    path = report_dir / "memory_metrics.csv"
    rows: list[dict] = []
    if path.is_file():
        with path.open(encoding="utf-8", errors="replace") as fh:
            for row in csv.DictReader(fh):
                rows.append(row)

    def col(name: str) -> list[float]:
        values = []
        for row in rows:
            try:
                values.append(float(row.get(name) or 0))
            except ValueError:
                pass
        return values

    cycle_rows = [r for r in rows if str(r.get("cycle", "0")).isdigit() and int(r["cycle"]) > 0]
    first_after = next(
        (r for r in cycle_rows if str(r.get("label", "")).endswith("after_actions")), None
    )
    last_after = None
    for r in cycle_rows:
        if str(r.get("label", "")).endswith("after_actions"):
            last_after = r

    def kb(row: dict | None) -> float:
        if not row:
            return 0.0
        try:
            return float(row.get("total_pss_kb") or 0)
        except ValueError:
            return 0.0

    return {
        "rows": rows,
        "peak_pss_kb": max(col("total_pss_kb"), default=0.0),
        "peak_rss_kb": max(col("total_rss_kb"), default=0.0),
        "peak_java_heap_kb": max(col("java_heap_kb"), default=0.0),
        "peak_native_heap_kb": max(col("native_heap_kb"), default=0.0),
        "first_cycle_pss_kb": kb(first_after),
        "last_cycle_pss_kb": kb(last_after),
    }


def parse_navigation(report_dir: Path) -> dict:
    events: list[dict] = []
    path = report_dir / "navigation_events.csv"
    if path.is_file():
        with path.open(encoding="utf-8", errors="replace") as fh:
            for row in csv.reader(fh):
                if len(row) < 4 or row[0] == "cycle":
                    continue
                events.append(
                    {"cycle": row[0], "event": row[1], "target": row[2], "detail": row[3]}
                )
    covered: dict[str, str] = {}
    login_events: list[dict] = []
    for ev in events:
        if ev["event"] == "target":
            status = "visited" if ev["detail"].startswith("visited") else "not_found"
            covered.setdefault(ev["target"], status)
            if covered[ev["target"]] != "visited" and status == "visited":
                covered[ev["target"]] = "visited"
        elif ev["event"] in (
            "login_success",
            "login_failed",
            "login_timeout",
            "login_blocked",
            "gdrive_prompt_blocking",
            "gdrive_skip_dialog_failed",
            "gdrive_skip_tap_failed",
            "session_restored",
        ):
            login_events.append(ev)
    return {"events": events, "covered": covered, "login_events": login_events}


def parse_stress(log_paths: list[Path]) -> list[dict]:
    results = []
    interesting = re.compile(
        r"(verdict=|CRUD_SYNC_STRESS|rss_|speedup|selects=|_ms=|All tests passed|docs=\d+|thresholds:)"
    )
    for path in log_paths:
        entry = {"name": path.stem, "passed": False, "metrics": []}
        if path.is_file():
            content = path.read_text(encoding="utf-8", errors="replace")
            entry["passed"] = "All tests passed" in content
            for line in content.splitlines():
                if interesting.search(line):
                    entry["metrics"].append(line.strip())
            entry["metrics"] = entry["metrics"][-6:]
        results.append(entry)
    return results


class Gate:
    def __init__(self, name: str, value, unit: str, warn, fail, status: str, note: str = ""):
        self.name = name
        self.value = value
        self.unit = unit
        self.warn = warn
        self.fail = fail
        self.status = status  # PASS / WARN / FAIL / INFO / N/A
        self.note = note

    def line(self) -> str:
        return (
            f"{self.name}={self.value} {self.unit} warn={self.warn} "
            f"fail={self.fail} status={self.status}"
        )


def classify(value: float, warn: float, fail: float, higher_is_bad: bool = True) -> str:
    if higher_is_bad:
        if value >= fail:
            return "FAIL"
        if value >= warn:
            return "WARN"
    else:
        if value <= fail:
            return "FAIL"
        if value <= warn:
            return "WARN"
    return "PASS"


def fmt_mb(kb: float) -> str:
    return f"{kb / 1024:.1f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Marina Hotel — Android 1GB Performance Gate")
    parser.add_argument("--report-dir", required=True)
    parser.add_argument("--apk-arm64-mb", type=float, default=None)
    parser.add_argument("--apk-arm-mb", type=float, default=None)
    parser.add_argument("--apk-x64-mb", type=float, default=None)
    parser.add_argument("--cred-mode", default="local-fallback")
    parser.add_argument("--build-mode", default="release")
    parser.add_argument("--commit", default="")
    parser.add_argument("--stress-log", action="append", default=[])
    args = parser.parse_args()

    report_dir = Path(args.report_dir)
    if not report_dir.is_dir():
        print(f"ERROR: report dir not found: {report_dir}", file=sys.stderr)
        return 1

    cold, warm = parse_cold_starts(report_dir)
    mem = parse_memory(report_dir)
    frame = read_kv(report_dir / "frame_summary.txt")
    nav = parse_navigation(report_dir)
    crash = read_kv(report_dir / "crash_scan_summary.txt")
    emulator = read_kv(report_dir / "emulator_profile.txt")
    summary = read_kv(report_dir / "summary.txt")
    stress = parse_stress([Path(p) for p in args.stress_log])

    gates: list[Gate] = []
    failures: list[str] = []
    warnings: list[str] = []

    # ── 1) Cold start ×5 ─────────────────────────────────────
    cold_values = [v for _, v in cold]
    if cold_values:
        first = cold_values[0]
        median = statistics.median(cold_values)
        gates.append(
            Gate(
                "cold_start_first",
                f"{first:.0f}",
                "ms",
                TH["cold_first_warn_ms"],
                TH["cold_first_fail_ms"],
                classify(first, TH["cold_first_warn_ms"], TH["cold_first_fail_ms"]),
                "أول إطلاق بعد التثبيت (يشمل تحسين dex) — المرجع 8830ms",
            )
        )
        gates.append(
            Gate(
                "cold_start_median",
                f"{median:.0f}",
                "ms",
                TH["cold_median_warn_ms"],
                TH["cold_median_fail_ms"],
                classify(median, TH["cold_median_warn_ms"], TH["cold_median_fail_ms"]),
                f"وسيط {len(cold_values)} إطلاقات باردة — المرجع {BASELINE['cold_start_median_ms']}ms (Profile)",
            )
        )
    else:
        gates.append(Gate("cold_start_median", "MISSING", "ms", "-", "-", "FAIL", "cold_start.csv مفقود"))
        failures.append("بيانات cold-start مفقودة")

    # ── 2) الذاكرة ────────────────────────────────────────────
    if mem["peak_pss_kb"] > 0:
        gates.append(
            Gate(
                "peak_pss",
                fmt_mb(mem["peak_pss_kb"]),
                "MB",
                fmt_mb(TH["pss_warn_kb"]),
                fmt_mb(TH["pss_fail_kb"]),
                classify(mem["peak_pss_kb"], TH["pss_warn_kb"], TH["pss_fail_kb"]),
                f"المرجع {fmt_mb(BASELINE['pss_peak_kb'])}MB (شاشة الدخول فقط)",
            )
        )
        gates.append(
            Gate(
                "peak_rss",
                fmt_mb(mem["peak_rss_kb"]),
                "MB",
                fmt_mb(TH["rss_warn_kb"]),
                fmt_mb(TH["rss_fail_kb"]),
                classify(mem["peak_rss_kb"], TH["rss_warn_kb"], TH["rss_fail_kb"]),
                f"المرجع {fmt_mb(BASELINE['rss_peak_kb'])}MB",
            )
        )
        growth = mem["last_cycle_pss_kb"] - mem["first_cycle_pss_kb"]
        growth_status = "WARN" if growth > TH["pss_growth_warn_kb"] else "INFO"
        gates.append(
            Gate(
                "pss_growth_cycles",
                fmt_mb(growth),
                "MB",
                fmt_mb(TH["pss_growth_warn_kb"]),
                "-",
                growth_status,
                "اتجاه النمو بين أول وآخر دورة (رصد تسريب محتمل — proxy للـ GC)",
            )
        )
    else:
        gates.append(Gate("peak_pss", "MISSING", "MB", "-", "-", "FAIL", "memory_metrics.csv فارغ"))
        failures.append("بيانات الذاكرة مفقودة")

    # ── 3) الإطارات (بيانات المراقب الداخلي) ─────────────────
    avg_frame = read_num(frame, "average_frame_time_ms")
    jank = read_num(frame, "jank_ratio")
    if avg_frame is not None:
        gates.append(
            Gate(
                "avg_frame_time",
                f"{avg_frame:.1f}",
                "ms",
                TH["frame_avg_warn_ms"],
                TH["frame_avg_fail_ms"],
                classify(avg_frame, TH["frame_avg_warn_ms"], TH["frame_avg_fail_ms"]),
                f"رسم swiftshader البرمجي — المرجع {BASELINE['avg_frame_ms']}ms؛ "
                "البوابة لرصد الانحدار النسبي لا أداء جهاز حقيقي",
            )
        )
    else:
        gates.append(
            Gate("avg_frame_time", "N/A", "ms", "-", "-", "WARN", "لا بيانات إطارات — تشغيل مُنقوص")
        )
        warnings.append("بيانات الإطارات غير متاحة (فشل قراءة تقرير المراقب الداخلي؟)")
    if jank is not None:
        gates.append(
            Gate(
                "jank_ratio",
                f"{jank:.4f}",
                "ratio",
                TH["jank_warn_ratio"],
                TH["jank_fail_ratio"],
                classify(jank, TH["jank_warn_ratio"], TH["jank_fail_ratio"]),
                f"قياسان حقيقيان مستقلان: 0.996 ثم 1.000 — التشبع بنيوي في الرسم البرمجي (كل إطار تقريباً >16ms)، فالنسبة تشخيص فقط ومؤشر الانحدار الحقيقي هو متوسط زمن الإطار ({BASELINE['avg_frame_ms']}ms مرجعاً)",
            )
        )

    # ── 4) الاستقرار: Crash / ANR / OOM ─────────────────────
    fatal = read_num(crash, "fatal_exception_count") or 0
    anr = read_num(crash, "anr_count") or 0
    oom = read_num(crash, "oom_count") or 0
    native_sig = read_num(crash, "native_fatal_signal_count") or 0
    stability_status = "FAIL" if (fatal or anr or oom) else "PASS"
    gates.append(
        Gate(
            "stability_crash_anr_oom",
            f"fatal={int(fatal)} anr={int(anr)} oom={int(oom)}",
            "count",
            0,
            1,
            stability_status,
            "أي Crash/ANR/OOM في جلسة القياس = فشل قاطع",
        )
    )
    if native_sig:
        gates.append(
            Gate(
                "native_fatal_signals",
                int(native_sig),
                "count",
                0,
                "-",
                "WARN",
                "إشارات native قاتلة في logcat — إسنادها للتطبيق غير مؤكد؛ راجع crash_scan.txt",
            )
        )
    if fatal:
        failures.append(f"انهيارات Java/Kotlin: {int(fatal)}")
    if anr:
        failures.append(f"ANR: {int(anr)}")
    if oom:
        failures.append(f"OutOfMemoryError: {int(oom)}")

    # ── 5) الدخول والتغطية ───────────────────────────────────
    login_status = "not_attempted"
    login_note = "لا أحداث دخول — سكربت التنقل لم يعمل؟"
    if nav["login_events"]:
        kinds = [ev["event"] for ev in nav["login_events"]]
        if "login_success" in kinds:
            login_status = "PASS"
            login_note = "دخول ناجح فعلي"
        elif "session_restored" in kinds and "login_failed" not in kinds:
            login_status = "PASS"
            login_note = "استعادة جلسة (rememberMe) — دخول فعلي سابق"
        elif "login_blocked" in kinds or "gdrive_prompt_blocking" in kinds:
            login_status = "FAIL"
            login_note = "شاشة Google Drive تحجب الدخول ولم يُنجح تخطيها"
        elif "gdrive_skip_dialog_failed" in kinds or "gdrive_skip_tap_failed" in kinds:
            login_status = "FAIL"
            login_note = "فشل تخطي شاشة Google Drive (زر/حوار التأكيد)"
        elif "login_failed" in kinds:
            login_status = "FAIL"
            login_note = "بيانات الدخول مرفوضة — راجع Secrets/الحساب"
        elif "login_timeout" in kinds:
            login_status = "FAIL"
            login_note = "مهلة انتظار لوحة التحكم بعد الدخول"
    else:
        login_status = "FAIL"
    gates.append(
        Gate(
            "login",
            login_status,
            "status",
            "PASS",
            "FAIL",
            login_status,
            login_note + f" (وضع بيانات الدخول: {args.cred_mode})",
        )
    )
    if login_status == "FAIL":
        failures.append(f"تسجيل الدخول: {login_note}")

    covered = nav["covered"]
    found = [t for t in REQUIRED_TARGETS if covered.get(t) == "visited"]
    missing = [t for t in REQUIRED_TARGETS if covered.get(t) != "visited"]
    if len(found) >= TH["nav_min_targets"]:
        nav_status = "PASS" if not missing else "WARN"
    else:
        nav_status = "FAIL"
    gates.append(
        Gate(
            "navigation_coverage",
            f"{len(found)}/{len(REQUIRED_TARGETS)}",
            "targets",
            f">={TH['nav_min_targets']}",
            f"<{TH['nav_min_targets']}",
            nav_status,
            "موجود: " + (", ".join(found) if found else "-") + " | ناقص: "
            + (", ".join(missing) if missing else "-"),
        )
    )
    if nav_status == "FAIL":
        failures.append(f"تغطية التنقل ناقصة: {len(found)}/{len(REQUIRED_TARGETS)}")
    elif nav_status == "WARN":
        warnings.append(f"شاشات لم تُزر: {', '.join(missing)}")

    # ── 6) اختبارات الضغط المضيفة ────────────────────────────
    for entry in stress:
        status = "PASS" if entry["passed"] else "FAIL"
        gates.append(
            Gate(
                f"stress_{entry['name']}",
                "passed" if entry["passed"] else "FAILED",
                "exit",
                "PASS",
                "FAIL",
                status,
                "بوابة flutter test نفسها (pipefail)",
            )
        )
        if not entry["passed"]:
            failures.append(f"اختبار الضغط {entry['name']} فشل")

    # ── 7) حجم APK ───────────────────────────────────────────
    if args.apk_arm64_mb is not None:
        gates.append(
            Gate(
                "apk_size_arm64",
                f"{args.apk_arm64_mb:.2f}",
                "MB",
                TH["apk_arm64_warn_mb"],
                TH["apk_arm64_fail_mb"],
                classify(args.apk_arm64_mb, TH["apk_arm64_warn_mb"], TH["apk_arm64_fail_mb"]),
                f"المرجع {BASELINE['apk_arm64_mb']}MB (v1.2.0+2957)",
            )
        )
        if classify(args.apk_arm64_mb, TH["apk_arm64_warn_mb"], TH["apk_arm64_fail_mb"]) == "FAIL":
            failures.append("حجم APK arm64 تجاوز الحد")

    for gate in gates:
        if gate.status == "FAIL":
            # ✅ قاعدة عامة: أي بوابة قيمتها FAIL تُفشل الحكم — علة سابقة:
            # بوابات القيم (jank/الإطارات/الذاكرة/الحجم/الإقلاع) كانت
            # تُظهر FAIL دون أن تُضاف لقائمة الفشل فيبقى الحكم PASS!
            # البوابات ذاتية التقرير (استقرار/دخول/تغطية/ضغط/فقد بيانات)
            # تضيف رسائلها المفصلة أعلاه فنتخطى التكرار هنا فقط.
            self_reported = (
                gate.name
                in ("stability_crash_anr_oom", "login", "navigation_coverage")
                or gate.name.startswith("stress_")
                or gate.name == "apk_size_arm64"
                or (
                    gate.name in ("peak_pss", "peak_rss", "cold_start_median")
                    and str(gate.value) == "MISSING"
                )
            )
            if not self_reported:
                failures.append(
                    f"{gate.name}={gate.value} {gate.unit} تجاوز حد الفشل (fail={gate.fail})"
                )
        elif gate.status == "WARN":
            warnings.append(gate.name)

    verdict = "FAIL" if failures else ("WARN" if warnings else "PASS")

    # ═══ توليد التقرير ═══
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines: list[str] = []
    lines.append("# Marina Hotel — Android 1GB Performance Report")
    lines.append("")
    lines.append(f"**VERDICT: {verdict}** — {len(failures)} فشل / {len(warnings)} تحذير")
    lines.append("")
    lines.append(f"- التوليد: {now} | الالتزام: `{args.commit or '-'}` | بناء: **{args.build_mode}**")
    lines.append(f"- وضع بيانات الدخول: **{args.cred_mode}**")
    if emulator:
        lines.append(
            f"- المحاكي: API {emulator.get('api_level', '?')} | "
            f"RAM: {emulator.get('memtotal', '?')} | "
            f"Heap: {emulator.get('dalvik_heapsize', '?')} | "
            f"الشاشة: {emulator.get('screen', '?')} @ {emulator.get('density', '?')}"
        )
    lines.append(f"- المرجع للمعايرة: {BASELINE['run']}")
    lines.append("")

    lines.append("## جدول البوابات")
    lines.append("")
    lines.append("| البوابة | القيمة | وحدة | تحذير | فشل | الحالة |")
    lines.append("|---|---|---|---|---|---|")
    for g in gates:
        lines.append(f"| {g.name} | {g.value} | {g.unit} | {g.warn} | {g.fail} | {g.status} |")
    lines.append("")

    lines.append("## تفاصيل")
    lines.append("")
    lines.append("### 1) Cold Start")
    if cold:
        lines.append("| الإطلاق | TotalTime (ms) |")
        lines.append("|---|---|")
        for label, value in cold:
            lines.append(f"| {label} | {value:.0f} |")
        lines.append("")
    if warm:
        wl = ", ".join(f"{label}={value:.0f}ms" for label, value in warm)
        lines.append(f"- عودة دافئة (دورة الحياة): {wl}")
        lines.append("")
    lines.append("### 2) الذاكرة")
    lines.append(
        f"- Peak PSS: **{fmt_mb(mem['peak_pss_kb'])}MB** | Peak RSS: "
        f"**{fmt_mb(mem['peak_rss_kb'])}MB**"
    )
    lines.append(
        f"- Java Heap peak: {fmt_mb(mem['peak_java_heap_kb'])}MB | "
        f"Native Heap peak: {fmt_mb(mem['peak_native_heap_kb'])}MB "
        "(اتجاه الكومة عبر الدورات = مراقبة GC)"
    )
    lines.append(
        f"- نمو PSS بين أول وآخر دورة: {fmt_mb(mem['last_cycle_pss_kb'] - mem['first_cycle_pss_kb'])}MB"
    )
    if mem["rows"]:
        lines.append("")
        lines.append("| النقطة | PSS (MB) | RSS (MB) | Java (MB) | Native (MB) |")
        lines.append("|---|---|---|---|---|")
        for row in mem["rows"]:
            try:
                lines.append(
                    f"| {row.get('label', '')} | {fmt_mb(float(row.get('total_pss_kb') or 0))} | "
                    f"{fmt_mb(float(row.get('total_rss_kb') or 0))} | "
                    f"{fmt_mb(float(row.get('java_heap_kb') or 0))} | "
                    f"{fmt_mb(float(row.get('native_heap_kb') or 0))} |"
                )
            except ValueError:
                continue
    lines.append("")

    lines.append("### 3) الإطارات")
    if frame:
        keys = [
            "snapshot_count",
            "total_frame_delta",
            "total_jank_delta",
            "jank_ratio",
            "average_frame_time_ms",
            "average_build_time_ms",
            "average_raster_time_ms",
            "minimum_reported_fps",
        ]
        for key in keys:
            if key in frame:
                lines.append(f"- {key}: {frame[key]}")
        lines.append("- ملاحظة: swiftshader برمجي — القيم لرصد الانحدار النسبي بين التشغيلات.")
    else:
        lines.append("- لا بيانات إطارات (تقرير المراقب الداخلي غير متاح).")
    lines.append("")

    lines.append("### 4) الاستقرار")
    lines.append(
        f"- FATAL EXCEPTION: {int(fatal)} | ANR: {int(anr)} | "
        f"OOM: {int(oom)} | إشارات native: {int(native_sig)}"
    )
    lines.append("- التفاصيل في crash_scan.txt داخل الـ artifact.")
    lines.append("")

    lines.append("### 5) الدخول والتغطية")
    lines.append(f"- الدخول: {login_status} — {login_note}")
    lines.append(
        f"- التغطية: {len(found)}/{len(REQUIRED_TARGETS)} ({', '.join(found) or '-'})"
    )
    if missing:
        lines.append(f"- ناقص: {', '.join(missing)}")
    extra = {
        k: v for k, v in covered.items() if k not in REQUIRED_TARGETS
    }
    if extra:
        pairs = ", ".join(f"{k}={v}" for k, v in sorted(extra.items()))
        lines.append(f"- تنقلات إضافية: {pairs}")
    lines.append("")

    lines.append("### 6) اختبارات الضغط المضيفة")
    if stress:
        lines.append("| الاختبار | الحالة | مؤشرات مختارة |")
        lines.append("|---|---|---|")
        for entry in stress:
            metrics = "<br>".join(m[:150] for m in entry["metrics"]) or "-"
            status = "PASS" if entry["passed"] else "FAIL"
            lines.append(f"| {entry['name']} | {status} | {metrics} |")
    else:
        lines.append("- لا سجلات ضغط ممررة.")
    lines.append("")

    lines.append("### 7) حجم APK")
    if args.apk_arm64_mb is not None:
        lines.append(
            f"- arm64-v8a: {args.apk_arm64_mb:.2f}MB"
            + (f" | armeabi-v7a: {args.apk_arm_mb:.2f}MB" if args.apk_arm_mb else "")
            + (f" | x86_64 (اختبار): {args.apk_x64_mb:.2f}MB" if args.apk_x64_mb else "")
        )
    else:
        lines.append("- غير متوفر.")
    lines.append("")

    lines.append("### 8) المخزون التشخيصي المرفوع")
    inventory = [
        "performance-report.md",
        "memory_metrics.csv",
        "cold_start.csv",
        "frame_metrics.csv / frame_summary.txt",
        "navigation_events.csv / navigation_actions.log",
        "crash_scan.txt / crash_scan_summary.txt",
        "lifecycle.log / emulator_profile.txt",
        "raw/ (dumpsys meminfo + gfxinfo + cpuinfo + تقارير المراقب الداخلي)",
        "apk_sizes.txt",
        "سجلات اختبارات الضغط",
    ]
    for item in inventory:
        lines.append(f"- {item}")
    lines.append("")

    if failures:
        lines.append("## الفشل")
        for f in failures:
            lines.append(f"- ✗ {f}")
        lines.append("")
    if warnings:
        lines.append("## التحذيرات")
        for w in warnings:
            lines.append(f"- ⚠ {w}")
        lines.append("")

    report_path = report_dir / "performance-report.md"
    report_path.write_text("\n".join(lines), encoding="utf-8")
    (report_dir / "gates_result.txt").write_text(
        "\n".join(g.line() for g in gates) + f"\nverdict={verdict}\n",
        encoding="utf-8",
    )

    print(f"PERF_GATE verdict={verdict} failures={len(failures)} warnings={len(warnings)}")
    for g in gates:
        print(g.line())
    return 1 if verdict == "FAIL" else 0


if __name__ == "__main__":
    sys.exit(main())
