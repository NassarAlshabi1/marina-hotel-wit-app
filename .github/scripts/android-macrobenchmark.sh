#!/usr/bin/env bash
# Only a disposable rooted emulator. Do not run this on a personal device.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$PWD/performance-evidence/macrobenchmark"
PKG=com.a.a
TEST_PKG=com.a.a.macrobenchmark
DEVICE_OUT=/sdcard/Android/media/com.a.a.macrobenchmark/benchmark-output
mkdir -p "$OUT"
[[ "$(adb shell getprop ro.kernel.qemu | tr -d '\r')" == "1" ]] || {
  echo '::error::A disposable emulator is required; no device was modified.'; exit 1;
}
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
adb shell am force-stop "$PKG"
adb shell pm clear "$PKG" | grep -q 'Success'

# Installing with Gradle during the run could change UIDs. Install once, then
# instrument the already-installed packages directly after both firewall checks.
for package in "$PKG" "$TEST_PKG"; do
  uid_value=$(adb shell pm list packages -U "$package" | tr -d '\r' |
    awk -v package="package:$package" '$1 == package { sub("uid:", "", $2); print $2 }')
  [[ "$uid_value" =~ ^[0-9]+$ ]] || { echo "::error::UID unavailable for $package"; exit 1; }
  adb shell iptables -I OUTPUT -m owner --uid-owner "$uid_value" -j REJECT
  adb shell ip6tables -I OUTPUT -m owner --uid-owner "$uid_value" -j REJECT
  adb shell iptables -C OUTPUT -m owner --uid-owner "$uid_value" -j REJECT
  adb shell ip6tables -C OUTPUT -m owner --uid-owner "$uid_value" -j REJECT
  printf '%s uid=%s IPv4=blocked IPv6=blocked\n' "$package" "$uid_value" >> "$OUT/isolation.txt"
done
adb shell mkdir -p "$DEVICE_OUT"
adb shell getprop > "$OUT/device-properties.txt"
adb shell cat /proc/meminfo > "$OUT/device-memory.txt"
adb logcat -c
set +e
adb shell am instrument -w -r \
  -e class com.marina.marina.macrobenchmark.EntryStartupBenchmark \
  -e marina.offlineVerified true \
  -e androidx.benchmark.suppressErrors EMULATOR \
  -e androidx.benchmark.output.enable true \
  -e additionalTestOutputDir "$DEVICE_OUT" \
  "$TEST_PKG/androidx.test.runner.AndroidJUnitRunner" | tr -d '\r' | tee "$OUT/instrumentation.txt"
runner_status=$?
set -e
collect_evidence
trap - EXIT
# adb may exit zero even when instrumentation failed or ran no tests.
if [[ "$runner_status" -ne 0 ]] || ! grep -Eq '^OK \(2 tests\)' "$OUT/instrumentation.txt"; then
  python3 - "$OUT/instrumentation.txt" <<'PY'
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text()[-2500:]
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
  --mode diagnostic --output "$OUT/summary.json"
python3 - "$OUT/summary.json" <<'PY'
import json, os, pathlib, sys
result = json.loads(pathlib.Path(sys.argv[1]).read_text())
evidence = {k: result[k] for k in ('status', 'scope', 'thresholdVerdict', 'releaseEligible', 'measurements')}
message = json.dumps(evidence).replace('%', '%25')
print(f'::notice title=Macrobenchmark measured evidence::{message}')
if summary := os.environ.get('GITHUB_STEP_SUMMARY'):
    with open(summary, 'a') as handle:
        handle.write('## Offline entry startup — emulator diagnostics only\n'
                     'Not a physical-device performance or release approval. '
                     'Requested RAM: 1024 MiB; actual RAM is recorded in device-memory.txt.\n```json\n'
                     + json.dumps(evidence, indent=2) + '\n```\n')
PY
