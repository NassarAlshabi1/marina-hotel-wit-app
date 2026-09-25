#!/usr/bin/env python3
# ==========================================================================
#  Marina Hotel — Performance Report Generator
#  يولّد تقرير أداء Markdown من ملفات المقاييس المجموعة من الـ emulator:
#    - results.txt          نتائج سيناريوهات integration_test (PASS/FAIL)
#    - cold_start.txt       مخرجات adb shell am start -W
#    - meminfo_final.txt    dumpsys meminfo الكامل النهائي
#    - meminfo_samples.txt  عينات TOTAL PSS أثناء الاختبارات
#    - gfxinfo.txt          dumpsys gfxinfo (إطارات متقطعة + percentiles)
#    - cpuinfo.txt          dumpsys cpuinfo
#    - cpu_samples.txt      عينات top أثناء الاختبارات
#    - gc.txt               سطور GC من logcat
#    - logcat.txt           logcat كامل
#
#  الاستخدام:
#    python3 scripts/generate_performance_report.py \
#      --metrics mobile/build/perf-integration \
#      --package com.marina.marina \
#      --output mobile/build/perf-integration/performance_report.md
# ==========================================================================

import argparse
import os
import re
import sys


def read_text(metrics_dir, name):
    path = os.path.join(metrics_dir, name)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return None


def parse_cold_start(text):
    """am start -W output: Status / LaunchState / TotalTime / WaitTime."""
    if not text:
        return None
    out = {}
    m = re.search(r"Status:\s*(\w+)", text)
    if m:
        out["status"] = m.group(1)
    m = re.search(r"LaunchState:\s*(\w+)", text)
    if m:
        out["launch_state"] = m.group(1)
    m = re.search(r"TotalTime:\s*(\d+)", text)
    if m:
        out["total_ms"] = int(m.group(1))
    m = re.search(r"WaitTime:\s*(\d+)", text)
    if m:
        out["wait_ms"] = int(m.group(1))
    return out or None


def parse_pss_kb(text):
    """dumpsys meminfo: TOTAL PSS line -> KB value."""
    if not text:
        return None
    m = re.search(r"TOTAL PSS:\s*(\d+)", text)
    if m:
        return int(m.group(1))
    m = re.search(r"TOTAL:\s*(\d+)", text)
    if m:
        return int(m.group(1))
    return None


def parse_pss_samples(text):
    """meminfo_samples.txt: عينات مفصولة بسطور '----- sample N ...'."""
    if not text:
        return []
    values = []
    for chunk in re.split(r"-{5,}", text):
        kb = parse_pss_kb(chunk)
        if kb:
            values.append(kb)
    return values


def parse_gfxinfo(text):
    """dumpsys gfxinfo top section: Janky frames + percentiles."""
    if not text:
        return None
    out = {}
    m = re.search(r"Total frames rendered:\s*(\d+)", text)
    if m:
        out["total_frames"] = int(m.group(1))
    m = re.search(r"Janky frames:\s*(\d+)\s*\(([\d.]+)%\)", text)
    if m:
        out["janky_frames"] = int(m.group(1))
        out["janky_percent"] = float(m.group(2))
    for pct in (50, 90, 95, 99):
        m = re.search(r"%dth percentile:\s*(\d+)ms" % pct, text)
        if m:
            out["p%d_ms" % pct] = int(m.group(1))
    m = re.search(r"Number Missed Vsync:\s*(\d+)", text)
    if m:
        out["missed_vsync"] = int(m.group(1))
    m = re.search(r"Number Slow UI thread:\s*(\d+)", text)
    if m:
        out["slow_ui_thread"] = int(m.group(1))
    return out or None


def parse_cpu_lines(text, package):
    """سطور top التي تخص الحزمة: استخراج %CPU تقريبياً من العمود."""
    if not text:
        return []
    values = []
    for line in text.splitlines():
        if package not in line:
            continue
        cols = line.split()
        percents = [c for c in cols if re.fullmatch(r"\d+(?:\.\d+)?", c)]
        if len(percents) >= 2:
            try:
                values.append(float(percents[-2]))
            except ValueError:
                pass
    return values


def parse_cpuinfo(text, package):
    """dumpsys cpuinfo: نسبة تحميل الحزمة مثل '0.5% TOTAL: 0.1% user + 0.4% kernel'."""
    if not text:
        return None
    m = re.search(
        re.escape(package) + r":\s*([\d.]+)%\s*TOTAL", text
    )
    if m:
        return float(m.group(1))
    return None


def parse_gc(text):
    if not text:
        return None
    lines = [ln for ln in text.splitlines() if ln.strip()]
    freed_total = 0
    m_freed = re.findall(r"GC freed\s+(\d+)", text)
    freed_total = sum(int(x) for x in m_freed)
    concurrent = len(re.findall(r"concurrent copying GC|Background concurrent", text))
    return {
        "count": len(lines),
        "freed_objects": freed_total,
        "concurrent_gc": concurrent,
    }


def detect_crashes(text):
    if not text:
        return None
    fatal = len(re.findall(r"FATAL EXCEPTION", text))
    anr = len(re.findall(r"ANR in com\.", text))
    return {"fatal_exceptions": fatal, "anr": anr}


def fmt_ms(ms):
    if ms is None:
        return "غير متوفر"
    return "%d ms (%.2f ث)" % (ms, ms / 1000.0)


def fmt_kb(kb):
    if kb is None:
        return "غير متوفر"
    if kb >= 1024:
        return "%d KB (%.1f MB)" % (kb, kb / 1024.0)
    return "%d KB" % kb


def build_report(metrics_dir, package, extra=None):
    results = read_text(metrics_dir, "results.txt")
    cold = parse_cold_start(read_text(metrics_dir, "cold_start.txt"))
    mem_final = parse_pss_kb(read_text(metrics_dir, "meminfo_final.txt"))
    samples = parse_pss_samples(read_text(metrics_dir, "meminfo_samples.txt"))
    gfx = parse_gfxinfo(read_text(metrics_dir, "gfxinfo.txt"))
    cpuinfo_total = parse_cpuinfo(read_text(metrics_dir, "cpuinfo.txt"), package)
    cpu_values = parse_cpu_lines(read_text(metrics_dir, "cpu_samples.txt"), package)
    gc = parse_gc(read_text(metrics_dir, "gc.txt"))
    crashes = detect_crashes(read_text(metrics_dir, "logcat.txt"))

    lines = []
    lines.append("# Marina Hotel — تقرير الأداء (Android Emulator)")
    lines.append("")
    lines.append("| البند | القيمة |")
    lines.append("|-------|--------|")
    lines.append("| الحزمة | `%s` |" % package)
    lines.append("| Emulator | API 34 — RAM 1GB (-memory 1024) — CPU 2 cores |")
    lines.append("| نوع البناء | Release APK (android-x64) |")
    if extra:
        for k, v in extra:
            lines.append("| %s | %s |" % (k, v))
    lines.append("")

    # ── سيناريوهات الاختبار ──
    lines.append("## نتائج سيناريوهات Integration Test")
    lines.append("")
    lines.append("| السيناريو | النتيجة |")
    lines.append("|-----------|---------|")
    scenario_order = [
        ("Cold Start", "Cold Start (إقلاع APK المثبَّت)"),
        ("Login", "Login"),
        ("Dashboard", "Dashboard"),
        ("Bookings", "Bookings"),
        ("Payments", "Payments"),
        ("Expenses", "Expenses"),
        ("Reports", "Reports"),
        ("Sync", "Sync"),
    ]
    parsed_results = {}
    if results:
        for line in results.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                parsed_results[k.strip()] = v.strip()
    any_fail = False
    for key, label in scenario_order:
        value = parsed_results.get(key)
        if value == "PASS":
            cell = "✅ PASS"
        elif value == "FAIL":
            cell = "❌ FAIL"
            any_fail = True
        elif value == "SKIP":
            cell = "⏭ SKIP"
        else:
            cell = "⚠️ لا نتيجة"
        lines.append("| %s | %s |" % (label, cell))
    lines.append("")

    # ── Cold Start ──
    lines.append("## Cold Start")
    lines.append("")
    if cold:
        lines.append("- الحالة: `%s`" % cold.get("status", "غير متوفر"))
        if "launch_state" in cold:
            lines.append("- LaunchState: `%s`" % cold["launch_state"])
        lines.append("- إجمالي زمن الإقلاع: %s" % fmt_ms(cold.get("total_ms")))
        lines.append("- WaitTime: %s" % fmt_ms(cold.get("wait_ms")))
    else:
        lines.append("- لا توجد بيانات cold start.")
    lines.append("")

    # ── الذاكرة ──
    lines.append("## الذاكرة (dumpsys meminfo)")
    lines.append("")
    lines.append("- TOTAL PSS النهائي: %s" % fmt_kb(mem_final))
    if samples:
        lines.append("- عدد عينات PSS أثناء الاختبارات: %d" % len(samples))
        lines.append("- أعلى PSS: %s" % fmt_kb(max(samples)))
        avg = sum(samples) / float(len(samples))
        lines.append("- متوسط PSS: %d KB (%.1f MB)" % (avg, avg / 1024.0))
    else:
        lines.append("- لا توجد عينات PSS أثناء الاختبارات.")
    lines.append("")

    # ── الرسوم ──
    lines.append("## الرسوم (dumpsys gfxinfo)")
    lines.append("")
    if gfx:
        lines.append("- إجمالي الإطارات: %s" % gfx.get("total_frames", "غير متوفر"))
        if "janky_percent" in gfx:
            lines.append(
                "- الإطارات المتقطعة: %d (%.2f%%)"
                % (gfx["janky_frames"], gfx["janky_percent"])
            )
        for pct in (50, 90, 95, 99):
            key = "p%d_ms" % pct
            if key in gfx:
                lines.append("- P%d: %d ms" % (pct, gfx[key]))
        if "missed_vsync" in gfx:
            lines.append("- Missed Vsync: %d" % gfx["missed_vsync"])
        if "slow_ui_thread" in gfx:
            lines.append("- Slow UI thread: %d" % gfx["slow_ui_thread"])
    else:
        lines.append("- لا توجد بيانات gfxinfo (قد لا تكون التطبيقات قد رسمت إطارات).")
    lines.append("")

    # ── المعالج ──
    lines.append("## المعالج (CPU)")
    lines.append("")
    if cpuinfo_total is not None:
        lines.append("- تحميل الحزمة (dumpsys cpuinfo): %.2f%%" % cpuinfo_total)
    if cpu_values:
        lines.append("- عينات top: %d — أعلى %%CPU: %.1f%%" % (len(cpu_values), max(cpu_values)))
    if cpuinfo_total is None and not cpu_values:
        lines.append("- لا توجد بيانات CPU.")
    lines.append("")

    # ── GC ──
    lines.append("## جامع القمامة (GC)")
    lines.append("")
    if gc:
        lines.append("- عدد أحداث GC في logcat: %d" % gc["count"])
        lines.append("- إجمالي الكائنات المحررة: %d" % gc["freed_objects"])
        lines.append("- أحداث concurrent copying GC: %d" % gc["concurrent_gc"])
    else:
        lines.append("- لا توجد أحداث GC مسجلة.")
    lines.append("")

    # ── Logcat ──
    lines.append("## Logcat — فحص الانهيارات")
    lines.append("")
    if crashes:
        lines.append("- FATAL EXCEPTION: %d" % crashes["fatal_exceptions"])
        lines.append("- ANR: %d" % crashes["anr"])
        if crashes["fatal_exceptions"] == 0 and crashes["anr"] == 0:
            lines.append("- ✅ لا توجد انهيارات أو ANR في logcat.")
        else:
            lines.append("- ⚠️ توجد انهيارات — راجع artifact الـ logcat الكامل.")
    else:
        lines.append("- لا يوجد logcat.")
    lines.append("")

    if any_fail:
        lines.append("> ⚠️ يوجد سيناريوهات فاشلة — راجع سجلات الاختبارات في الـ artifacts.")
        lines.append("")

    return "\n".join(lines), any_fail


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--metrics", required=True)
    parser.add_argument("--package", default="com.marina.marina")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    if not os.path.isdir(args.metrics):
        print("metrics dir not found: %s" % args.metrics, file=sys.stderr)
        sys.exit(2)

    report, any_fail = build_report(args.metrics, args.package)
    os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(report)
    print(report)
    # exit code 3 = يوجد سيناريوهات فاشلة (التقرير نفسه سليم)
    sys.exit(3 if any_fail else 0)


if __name__ == "__main__":
    main()
