"""Mocked ADB control-flow checks, NOT device/network or performance measurements."""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FAKE_ADB = r'''#!/usr/bin/env python3
import os,sys,json
from pathlib import Path
a=sys.argv[1:]; mode=os.environ['MOCK_MODE']
with open(os.environ['MOCK_LOG'],'a') as f:f.write(json.dumps(a)+'\n')
if a==['shell','getprop','ro.kernel.qemu']:print('0' if mode=='physical' else '1')
elif a==['shell','cat','/proc/meminfo']:
 if mode=='ram_unreadable':sys.exit(1)
 print('MemTotal: 2534548 kB' if mode=='ram_too_large' else 'MemTotal: 921600 kB')
elif a[:3]==['shell','pm','clear']:print('Success')
elif a[:4]==['shell','pm','list','packages']:
 if mode!='no_uid':print('package:'+a[-1]+' uid:'+('10002' if a[-1].endswith('macrobenchmark') else '10001'))
elif a[:3]==['shell','ip6tables','-C'] and mode=='firewall_fail':sys.exit(1)
elif a[:2]==['shell','test'] and mode=='device_stale':sys.exit(1)
elif a[:3]==['shell','am','instrument'] and mode=='timeout':sys.exit(124)
elif a[:3]==['shell','am','instrument']:print('OK (0 tests)' if mode=='zero_tests' else 'OK (2 tests)')
elif a[0]=='pull':
 out=Path(a[-1]);out.mkdir(parents=True,exist_ok=True)
 data={'context':{'build':{'fingerprint':'synthetic-emulator'},'memTotalBytes':(2595377152 if mode=='ram_context_mismatch' else 943718400)},'benchmarks':[{'className':'com.marina.marina.macrobenchmark.EntryStartupBenchmark','name':n,'metrics':{'timeToInitialDisplayMs':{'runs':[v]*8}}} for n,v in [('coldStartup',3000),('warmStartup',1000)]]}
 (out/'synthetic-benchmarkData.json').write_text(json.dumps({} if mode=='bad_json' else data))
'''


class BenchmarkHarnessTest(unittest.TestCase):
    def scenario(self, mode):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "bin").mkdir()
            for name in (".github/scripts/android-macrobenchmark.sh",
                         ".github/scripts/performance-gate.py", ".github/scripts/benchmark-environment.py",
                         "config/benchmark/entry-startup.json"):
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy(ROOT / name, destination)
            adb = root / "bin/adb"
            adb.write_text(FAKE_ADB)
            adb.chmod(0o755)
            output = root / "performance-evidence/macrobenchmark"
            if mode == "host_stale":
                output.mkdir(parents=True)
            log = root / "calls.jsonl"
            env = dict(os.environ, PATH=str(root / "bin") + ":" + os.environ["PATH"],
                       MOCK_MODE=mode, MOCK_LOG=str(log))
            # Never append synthetic results to a real CI step summary.
            env.pop("GITHUB_STEP_SUMMARY", None)
            result = subprocess.run(["bash", str(root / ".github/scripts/android-macrobenchmark.sh")],
                                    env=env, capture_output=True, text=True, timeout=20)
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            self.assertEqual(mode == "valid", result.returncode == 0,
                             (mode, result.returncode, result.stdout, result.stderr))
            if mode in ("physical", "host_stale", "ram_too_large", "ram_unreadable"):
                self.assertFalse(any(call[0] in ("root", "install") for call in calls))
            if mode in ("physical", "host_stale", "device_stale", "no_uid", "firewall_fail", "ram_too_large", "ram_unreadable"):
                self.assertFalse(any(call[:3] == ["shell", "am", "instrument"] for call in calls))
            if mode == "valid":
                instrument = next(i for i, call in enumerate(calls)
                                  if call[:3] == ["shell", "am", "instrument"])
                rules = [call for call in calls[:instrument]
                         if call[:3] in (["shell", "iptables", "-C"], ["shell", "ip6tables", "-C"])]
                self.assertEqual(4, len(rules))
                for rule in rules:
                    # Target UID: block every interface. Test UID: block all except
                    # loopback, which is mandatory for Perfetto's local HTTP server.
                    uid = rule[rule.index("--uid-owner") + 1]
                    self.assertIn(uid, ("10001", "10002"))
                    self.assertIn(rule[:2] + ["-I"] + rule[3:], calls[:instrument])
                    self.assertEqual(["!", "-o", "lo"] if uid == "10002" else ["-m", "owner", "--uid-owner"],
                                     rule[4:7])
                    self.assertEqual(["-j", "REJECT"], rule[-2:])
                summary = json.loads((output / "summary.json").read_text())
                self.assertEqual("DIAGNOSTIC_ONLY", summary["status"])
                self.assertFalse(summary["releaseEligible"])
                environment = json.loads((output / "environment.json").read_text())
                self.assertEqual("RAM_VERIFIED_ONLY", environment["status"])
            if mode == "ram_context_mismatch":
                self.assertNotIn("::notice title=Macrobenchmark measured evidence::", result.stdout)
                self.assertEqual("INVALID_ENVIRONMENT", json.loads((output / "environment.json").read_text())["status"])
                self.assertFalse((output / "summary.json").exists())

    def test_physical_device_rejected_before_modification(self):
        self.scenario("physical")

    def test_stale_host_evidence_rejected(self):
        self.scenario("host_stale")

    def test_stale_device_evidence_rejected(self):
        self.scenario("device_stale")

    def test_unknown_uid_blocks_launch(self):
        self.scenario("no_uid")

    def test_ipv6_firewall_failure_blocks_launch(self):
        self.scenario("firewall_fail")

    def test_zero_tests_is_failure_even_with_zero_adb_exit(self):
        self.scenario("zero_tests")

    def test_invalid_json_is_not_success(self):
        self.scenario("bad_json")

    def test_timeout_is_failure(self):
        self.scenario("timeout")

    def test_verified_external_isolation_allows_only_test_loopback(self):
        self.scenario("valid")

    def test_oversized_ram_rejected_before_install(self):
        self.scenario("ram_too_large")

    def test_unreadable_ram_rejected_before_install(self):
        self.scenario("ram_unreadable")

    def test_androidx_ram_mismatch_rejects_final_evidence(self):
        self.scenario("ram_context_mismatch")
