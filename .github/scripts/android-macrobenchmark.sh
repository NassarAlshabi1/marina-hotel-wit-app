#!/usr/bin/env bash
# Only a disposable rooted emulator. Do not run this on a personal device.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$PWD/performance-evidence/macrobenchmark"
PKG=com.a.a
TEST_PKG=com.a.a.macrobenchmark
DEVICE_OUT=/sdcard/Android/media/com.a.a.macrobenchmark/benchmark-output
[[ ! -e "$OUT" ]] || {
  echo '::error::Evidence directory already exists; archive it before a fresh run.'; exit 1;
}
mkdir -p "$OUT"
ADB_BIN=$(command -v adb)
adb() { timeout --signal=TERM --kill-after=10s 90s "$ADB_BIN" "$@"; }
phase() {
  printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$OUT/phases.txt"
  echo "::notice title=Macrobenchmark phase::$*"
}
phase 'Harness started'
[[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]] || {
  echo '::error::A disposable emulator is required; no device was modified.'; exit 1;
}
phase 'Disposable emulator guard passed'
# Record only whitelisted host memory settings (never full process arguments).
python3 - "$OUT/emulator-memory-config.json" <<'PYCONFIG'
import json, os, pathlib, re, sys
configuration = {"requestedRamMiB": 1024, "avdMemorySettings": [], "hardwareMemorySettings": [], "qemuMemoryArguments": []}
# Recent SDKs also use XDG/ANDROID_USER_HOME rather than ~/.android.
roots = {pathlib.Path.home() / ".android/avd", pathlib.Path.home() / ".config/.android/avd"}
if os.environ.get("ANDROID_AVD_HOME"):
    roots.add(pathlib.Path(os.environ["ANDROID_AVD_HOME"]))
if os.environ.get("ANDROID_USER_HOME"):
    roots.add(pathlib.Path(os.environ["ANDROID_USER_HOME"]) / "avd")
for root in sorted(roots):
    for filename, key in (("config.ini", "avdMemorySettings"), ("hardware-qemu.ini", "hardwareMemorySettings")):
        for path in root.glob("*.avd/" + filename):
            for line in path.read_text(errors="replace").splitlines():
                name, separator, value = line.partition("=")
                if separator and name.strip() == "hw.ramSize" and re.fullmatch(r"[0-9]+[KMG]?", value.strip()):
                    configuration[key].append(value.strip())
for path in pathlib.Path("/proc").glob("[0-9]*/cmdline"):
    try:
        args = path.read_bytes().decode(errors="replace").split("\0")
        if not args or not (pathlib.Path(args[0]).name.startswith("qemu-system-") or pathlib.Path(args[0]).name == "emulator"):
            continue
        for i, arg in enumerate(args[:-1]):
            if arg in ("-m", "-memory") and re.fullmatch(r"(?:size=)?[0-9]+[KMG]?", args[i + 1]):
                configuration["qemuMemoryArguments"].append(args[i + 1])
    except (OSError, ValueError):
        continue
pathlib.Path(sys.argv[1]).write_text(json.dumps(configuration, indent=2) + "\n")
print("::notice title=Emulator memory configuration::" + json.dumps(configuration))
PYCONFIG
# Fail before installing or clearing packages if the requested profile was ignored.
adb shell cat /proc/meminfo > "$OUT/device-memory.txt"
python3 .github/scripts/benchmark-environment.py --meminfo "$OUT/device-memory.txt" \
  --output "$OUT/environment-preflight.json"
adb root
adb wait-for-device

collect_evidence() {
  adb shell dumpsys meminfo "$PKG" > "$OUT/memory.txt" 2>&1 || true
  adb shell dumpsys gfxinfo "$PKG" framestats > "$OUT/frames.txt" 2>&1 || true
  adb logcat -d -b crash > "$OUT/crash-buffer.txt" 2>&1 || true
  adb logcat -d -b events > "$OUT/events.txt" 2>&1 || true
  adb pull "$DEVICE_OUT" "$OUT/raw" > "$OUT/pull.txt" 2>&1 || true
}
trap collect_evidence EXIT
adb install -t mobile/build/app/outputs/apk/benchmark/app-benchmark.apk
adb install -t mobile/build/macrobenchmark/outputs/apk/benchmark/macrobenchmark-benchmark.apk
phase 'Both benchmark APKs installed'
adb shell am force-stop "$PKG"
adb shell pm clear "$PKG" | grep -q 'Success'

# Installing with Gradle during the run could change UIDs. Install once, then
# instrument the already-installed packages directly after both firewall checks.
for package in "$PKG" "$TEST_PKG"; do
  uid_value=$(adb shell pm list packages -U "$package" | tr -d '\r' |
    awk -v package="package:$package" '$1 == package { sub("uid:", "", $2); print $2 }')
  [[ "$uid_value" =~ ^[0-9]+$ ]] || { echo "::error::UID unavailable for $package"; exit 1; }
  # AndroidX trace processing uses an on-device localhost HTTP server. Allow
  # only the test UID's loopback IPC, never its external interfaces. The target
  # application UID retains the stricter all-interface block.
  network_scope=()
  loopback=blocked
  if [[ "$package" == "$TEST_PKG" ]]; then
    network_scope=('!' '-o' 'lo')
    loopback=allowed-for-local-trace-processing
  fi
  adb shell iptables -I OUTPUT "${network_scope[@]}" -m owner --uid-owner "$uid_value" -j REJECT
  adb shell ip6tables -I OUTPUT "${network_scope[@]}" -m owner --uid-owner "$uid_value" -j REJECT
  adb shell iptables -C OUTPUT "${network_scope[@]}" -m owner --uid-owner "$uid_value" -j REJECT
  adb shell ip6tables -C OUTPUT "${network_scope[@]}" -m owner --uid-owner "$uid_value" -j REJECT
  printf '%s uid=%s externalIPv4=blocked externalIPv6=blocked loopback=%s\n' "$package" "$uid_value" "$loopback" >> "$OUT/isolation.txt"
done
phase 'External IPv4/IPv6 blocked for both UIDs; only test-local loopback allowed'
adb shell test ! -e "$DEVICE_OUT" || {
  echo '::error::Device output directory is not fresh; use a new disposable emulator.'; exit 1;
}
adb shell mkdir -p "$DEVICE_OUT"
adb shell getprop > "$OUT/device-properties.txt"
adb logcat -b all -c
phase 'Starting instrumentation (10 minute maximum)'
set +e
timeout --signal=TERM --kill-after=10s 10m "$ADB_BIN" shell am instrument -w -r \
  -e class com.marina.marina.macrobenchmark.EntryStartupBenchmark \
  -e marina.offlineVerified true \
  -e androidx.benchmark.suppressErrors EMULATOR \
  -e androidx.benchmark.output.enable true \
  -e additionalTestOutputDir "$DEVICE_OUT" \
  "$TEST_PKG/androidx.test.runner.AndroidJUnitRunner" 2>&1 | tr -d '\r' | tee "$OUT/instrumentation.txt"
runner_status=$?
set -e
phase "Instrumentation returned status $runner_status"
if [[ "$runner_status" -ne 0 ]] || ! grep -Eq '^OK \(2 tests\)' "$OUT/instrumentation.txt"; then
  # Capture live compiler/runner state before stopping it. Filter framework tags,
  # not application HTTP logs, so annotations do not expose request credentials.
  adb shell ps -A > "$OUT/processes-at-failure.txt" 2>&1 || true
  adb logcat -d -v brief 'Benchmark:V' 'Macrobenchmark:V' 'PerfettoCapture:V' 'PerfettoHttpServer:V' '*:S' \
    > "$OUT/benchmark-log.txt" 2>&1 || true
  adb logcat -d -b crash > "$OUT/crash-at-failure.txt" 2>&1 || true
  adb logcat -d -v brief 'lmkd:I' '*:S' > "$OUT/low-memory-at-failure.txt" 2>&1 || true
  python3 - "$OUT" <<'PYDIAG'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
processes = [line for line in (root / 'processes-at-failure.txt').read_text().splitlines()
             if re.search(r'dex2oat|artd|com[.]a[.]a|perfetto|trace_processor', line)]
logs = (root / 'benchmark-log.txt').read_text().splitlines()[-20:]
# Report only exception class names for our packages, not exception messages.
crashes = []
in_target = False
for line in (root / 'crash-at-failure.txt').read_text().splitlines():
    if 'Process: ' in line:
        in_target = bool(re.search(r'Process: com[.]a[.]a(?:[.]macrobenchmark)?[, :]', line))
    if in_target:
        crashes.extend(re.findall(r'\b(?:[\w$]+[.])+[\w$]*(?:Error|Exception)\b', line))
kills = [line for line in (root / 'low-memory-at-failure.txt').read_text().splitlines()
         if re.search(r"com[.]a[.]a(?:[.]macrobenchmark)?['\" :\s]", line)][-8:]
text = ('Target exception classes: ' + ', '.join(sorted(set(crashes))) +
        '\nLow-memory events:\n' + '\n'.join(kills) +
        '\nLive processes:\n' + '\n'.join(processes) + '\nBenchmark log:\n' + '\n'.join(logs))[:3000]
text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print(f'::notice title=Macrobenchmark failure diagnostics::{text}')
PYDIAG
  adb shell am force-stop "$TEST_PKG" || true
fi
collect_evidence
trap - EXIT
# adb may exit zero even when instrumentation failed or ran no tests.
if [[ "$runner_status" -ne 0 ]] || ! grep -Eq '^OK \(2 tests\)' "$OUT/instrumentation.txt"; then
  python3 - "$OUT/instrumentation.txt" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
markers = ('Exception', 'Error', 'FAIL', 'INSTRUMENTATION_STATUS: test=', 'INSTRUMENTATION_RESULT:', 'marina.phase=')
selected = [line for line in lines if any(marker in line for marker in markers)]
text = '\n'.join(selected[:12] + lines[-12:])[:2500]
text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print(f'::error title=Macrobenchmark instrumentation failed::{text}')
PY
  exit 1
fi
if grep -Eq '(Process: |Cmdline: )com[.]a[.]a([,:[:space:]]|$)' "$OUT/crash-buffer.txt" ||
   grep -Eq 'am_anr.*com[.]a[.]a([,:[:space:]]|$)' "$OUT/events.txt"; then
  echo '::error::Target-application crash/ANR evidence detected'; exit 1
fi
mapfile -t reports < <(find "$OUT/raw" -type f -name '*-benchmarkData.json' | sort)
[[ "${#reports[@]}" -gt 0 ]] || { echo '::error::Benchmark JSON output is missing'; exit 1; }
python3 .github/scripts/performance-gate.py \
  --results "${reports[@]}" --policy config/benchmark/entry-startup.json \
  --mode diagnostic --output "$OUT/metrics.json"
python3 .github/scripts/benchmark-environment.py --meminfo "$OUT/device-memory.txt" \
  --summary "$OUT/metrics.json" --output "$OUT/environment.json"
# Publish the canonical summary only after both metric and RAM checks pass.
cp "$OUT/metrics.json" "$OUT/summary.json"
python3 - "$OUT/summary.json" <<'PY'
import json, os, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
evidence = {k: result[k] for k in ('status', 'scope', 'thresholdVerdict', 'releaseEligible', 'context', 'measurements')}
message = json.dumps(evidence).replace('%', '%25')
print(f'::notice title=Macrobenchmark measured evidence::{message}')
if summary := os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(summary, 'a') as handle:
        handle.write('## Offline entry startup — emulator diagnostics only\n'
                     'Not a physical-device performance or release approval. '
                     'Requested RAM: 1024 MiB; actual RAM is recorded in device-memory.txt.\n```json\n'
                     + json.dumps(evidence, indent=2) + '\n```\n')
PY
