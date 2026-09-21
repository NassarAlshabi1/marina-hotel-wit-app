#!/usr/bin/env bash
# Launch forensics for the "app closes right after MainActivity, no stack
# trace" failure — runs INSIDE reactivecircus/android-emulator-runner, i.e.
# with a booted KVM-accelerated emulator and adb on PATH.
#
# The action executes the `script:` input line by line (each line in its own
# `sh -c`), so shell variables and functions only survive if the whole probe
# lives in a file and is invoked as a single command.
set -u

cd "$(dirname "$0")/../.." || exit 1
ROOT="$(pwd)"
APK="$ROOT/mobile/build/app/outputs/apk/debug/app-debug.apk"
OUT="$ROOT/probe"
PKG="com.a.a"
mkdir -p "$OUT"

echo "=== environment ==="
adb wait-for-device
adb shell getprop ro.build.version.release
adb shell getprop ro.build.version.sdk
adb shell getprop ro.product.cpu.abi
ls -la "$APK"

echo "=== install ==="
adb install -r -t "$APK" 2>&1 | tee "$OUT/install.txt"

snap() {
  label="$1"
  adb logcat -d -v threadtime > "$OUT/logcat-$label.txt" 2>&1
  adb logcat -d -b crash -v threadtime > "$OUT/logcat-crash-$label.txt" 2>&1
  # The OS's own record of why the process ended (Java crash / native crash /
  # ANR / low memory / SIGKILL) — available since Android 11.
  adb shell dumpsys activity exit-info "$PKG" > "$OUT/exit-info-$label.txt" 2>&1
  # Human-sized extraction of just the interesting lines.
  grep -E "FATAL|AndroidRuntime|$PKG|MarinaDiag" "$OUT/logcat-$label.txt" > "$OUT/interesting-$label.txt" 2>&1
  echo "--- interesting lines ($label) ---"
  tail -n 80 "$OUT/interesting-$label.txt"
}

launch() {
  label="$1"
  component="$2"
  echo "=== launching $label -> $component ==="
  adb logcat -c
  adb shell am force-stop "$PKG"
  sleep 2
  adb shell am start -W -n "$component" > "$OUT/am-start-$label.txt" 2>&1
  cat "$OUT/am-start-$label.txt"
  sleep 3
  pid3="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
  sleep 17
  pid20="$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r')"
  if [ -n "$pid20" ]; then
    echo "STATE[$label]: ALIVE (pid after 3s='$pid3', after 20s='$pid20')"
    echo "ALIVE pid3=$pid3 pid20=$pid20" > "$OUT/state-$label.txt"
  else
    echo "STATE[$label]: DEAD (pid after 3s='$pid3')"
    echo "DEAD pid3=$pid3" > "$OUT/state-$label.txt"
  fi
  snap "$label"
}

launch main  "$PKG/com.marina.marina.MainActivity"
launch bare  "$PKG/com.marina.marina.diagnostics.BareLaunchActivity"
launch probe "$PKG/com.marina.marina.diagnostics.LaunchProbeActivity"

echo "=== marina-diag files ==="
for f in stages.log crash.log; do
  {
    echo "--- external files dir ---"
    adb shell "run-as $PKG cat /sdcard/Android/data/$PKG/files/marina-diag/$f" 2>&1
    echo "--- internal files dir ---"
    adb shell "run-as $PKG cat files/marina-diag/$f" 2>&1
  } > "$OUT/$f"
  echo "--- $f ---"
  cat "$OUT/$f"
done

echo "=== tombstones / anr (adb root) ==="
adb root || true
sleep 3
adb wait-for-device || true
adb shell 'ls -la /data/tombstones 2>/dev/null; cat /data/tombstones/* 2>/dev/null | head -400' > "$OUT/tombstones.txt" 2>&1
adb shell 'ls -la /data/anr 2>/dev/null; cat /data/anr/* 2>/dev/null | head -400' > "$OUT/anr.txt" 2>&1

echo "=== summary ==="
for f in "$OUT"/state-*.txt; do echo "$f => $(cat "$f")"; done
echo "--- crash buffer of the probe run ---"
head -c 4000 "$OUT/logcat-crash-probe.txt" 2>/dev/null
echo
echo "=== probe done ==="

# ── Gate ────────────────────────────────────────────────────────────────────
# Evidence-only green runs hid the launch crash for days (the workflow went
# green while every launch died). The probe must FAIL the build when the real
# MainActivity cannot survive a launch, so launch regressions gate CI. The
# bare/probe launches stay informational (framework bisection).
main_state="$(cat "$OUT/state-main.txt" 2>/dev/null || echo MISSING)"
if [[ "$main_state" == ALIVE* ]]; then
  echo "GATE[main]: PASS — $PKG survived MainActivity launch for 20s ($main_state)"
  exit 0
fi
echo "GATE[main]: FAIL — the real MainActivity did not survive launch ($main_state)"
echo "Evidence: state-*.txt, logcat-crash-*.txt, exit-info-*.txt in the uploaded artifact."
exit 1
