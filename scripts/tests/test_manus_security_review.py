#!/usr/bin/env python3
"""Regression tests for scripts/manus_security_review.py.

Covers the PR #636 failure (run 39314309799): a 1490-file pull request produced a
4.75 MB redacted diff, and the script aborted with
"Redacted diff exceeds the configured 1.5 MB review limit" before contacting the
Manus API. The advisory review must now plan a bounded, prioritised review and
report the files it could not cover instead of failing the check.

Run with: python3 -m unittest discover -s scripts/tests -v
"""
from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "manus_security_review.py"
_spec = importlib.util.spec_from_file_location("manus_security_review", SCRIPT)
assert _spec and _spec.loader
manus = importlib.util.module_from_spec(_spec)
sys.modules["manus_security_review"] = manus
_spec.loader.exec_module(manus)


def make_diff(files: dict[str, str], context_lines: int = 5) -> str:
    """Build a synthetic unified diff with one section per file."""
    parts = []
    for path, body in files.items():
        added = "\n".join(f"+{body}-{index}" for index in range(context_lines))
        parts.append(
            f"diff --git a/{path} b/{path}\n"
            f"index 1111111..2222222 100644\n"
            f"--- a/{path}\n"
            f"+++ b/{path}\n"
            f"@@ -1,{context_lines} +1,{context_lines} @@\n"
            f"{added}\n"
        )
    return "".join(parts)


class SectionHelpersTest(unittest.TestCase):
    def test_section_path_prefers_the_added_file(self):
        section = "diff --git a/lib/old.dart b/lib/new.dart\n--- a/lib/old.dart\n+++ b/lib/new.dart\n@@\n"
        self.assertEqual(manus.section_path(section), "lib/new.dart")

    def test_section_path_handles_added_files_without_a_plus_header(self):
        section = "diff --git a/a/b.dart b/a/b.dart\nnew file mode 100644\n+++ /dev/null\n"
        self.assertEqual(manus.section_path(section), "a/b.dart")

    def test_workflow_and_script_files_outrank_plain_dart(self):
        workflow = make_diff({".github/workflows/ci.yml": "run: curl x"})
        dart = make_diff({"mobile/lib/main.dart": "void main() {}"})
        self.assertGreater(
            manus.section_weight(workflow),
            manus.section_weight(dart),
        )

    def test_sensitive_content_adds_a_bonus(self):
        plain = make_diff({"mobile/lib/widget.dart": "build() {}"})
        sensitive = make_diff({"mobile/lib/widget.dart": "apiKey = token"})
        self.assertGreater(manus.section_weight(sensitive), manus.section_weight(plain))

    def test_split_oversized_keeps_every_piece_within_the_limit(self):
        section = make_diff({"lib/big.dart": "x" * 200}, context_lines=200)
        self.assertGreater(len(section), manus.MAX_DIFF_CHUNK_CHARS)
        pieces = manus.split_oversized(section, 500)
        self.assertTrue(all(len(piece) <= 500 for piece in pieces))
        self.assertEqual("".join(pieces), section)

    def test_split_oversized_hard_splits_a_single_long_line(self):
        """Regression: one minified line produced a 5697-char chunk on PR #636."""
        section = "diff --git a/a.js b/a.js\n+++ b/a.js\n@@\n+" + ("x" * 12_000) + "\n"
        pieces = manus.split_oversized(section, 5_000)
        self.assertTrue(pieces, "an oversized section must still produce pieces")
        self.assertTrue(
            all(len(piece) <= 5_000 for piece in pieces),
            f"piece lengths exceeded the limit: {[len(p) for p in pieces]}",
        )
        self.assertEqual("".join(pieces), section)

    def test_no_chunk_exceeds_the_limit_for_a_real_world_shape(self):
        files = {
            "mobile/lib/normal.dart": "body",
            "web/assets/vendor.js": "y" * 9_000,
        }
        plan = manus.plan_review(make_diff(files, context_lines=20), max_chunks=6)
        self.assertTrue(plan.chunks)
        self.assertTrue(all(len(chunk) <= manus.MAX_DIFF_CHUNK_CHARS for chunk in plan.chunks))

    def test_pack_pieces_respects_the_chunk_limit(self):
        # 100 + 100 packs into one chunk; the third 400-char piece cannot join it.
        pieces = ["a" * 100, "b" * 100, "c" * 400]
        chunks = manus.pack_pieces(pieces, 500)
        self.assertEqual(len(chunks), 2)
        self.assertTrue(all(len(chunk) <= 500 for chunk in chunks))
        self.assertEqual("".join(chunks), "".join(pieces))
        # Pieces larger than half the limit each need their own chunk.
        self.assertEqual(len(manus.pack_pieces(["x" * 300, "y" * 300, "z" * 300], 500)), 3)


class PlanReviewTest(unittest.TestCase):
    def test_budget_caps_chunk_count_and_accounts_for_every_file(self):
        files = {f"mobile/lib/screen_{index}.dart": "body" for index in range(400)}
        plan = manus.plan_review(make_diff(files), max_chunks=3)
        self.assertLessEqual(len(plan.chunks), 3)
        self.assertTrue(all(len(chunk) <= manus.MAX_DIFF_CHUNK_CHARS for chunk in plan.chunks))
        self.assertEqual(len(plan.reviewed) + len(plan.excluded), plan.total_sections)
        self.assertEqual(plan.total_sections, 400)
        self.assertGreater(len(plan.excluded), 0, "a 400-file diff cannot fit three chunks")

    def test_small_diff_reviews_everything(self):
        files = {"mobile/lib/a.dart": "a", ".github/workflows/ci.yml": "b"}
        plan = manus.plan_review(make_diff(files), max_chunks=12)
        self.assertEqual(sorted(plan.reviewed), sorted(files))
        self.assertEqual(plan.excluded, [])

    def test_high_priority_files_are_reviewed_first(self):
        files = {f"mobile/lib/screen_{index}.dart": "body" for index in range(300)}
        files[".github/workflows/ci.yml"] = "run: echo"
        files["scripts/deploy.sh"] = "echo"
        plan = manus.plan_review(make_diff(files), max_chunks=2)
        self.assertIn(".github/workflows/ci.yml", plan.reviewed)
        self.assertIn("scripts/deploy.sh", plan.reviewed)

    def test_invalid_budget_is_rejected(self):
        with self.assertRaises(ValueError):
            manus.plan_review(make_diff({"a.dart": "a"}), max_chunks=0)


class MainTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.diff_file = Path(self._tmp.name) / "review.diff"
        self.json_out = Path(self._tmp.name) / "report.json"
        self.md_out = Path(self._tmp.name) / "report.md"

    def run_main(self, diff: str, extra_env=None, extra_argv=None, stub_reports=None):
        self.diff_file.write_text(diff, encoding="utf-8")
        env = {"MANUS_API_KEY": "dummy-key"}
        env.update(extra_env or {})
        calls: list[str] = []

        def fake_review(api_key, prompt):
            calls.append(prompt)
            if stub_reports is not None:
                return stub_reports[min(len(calls) - 1, len(stub_reports) - 1)]
            return {
                "summary": "ok",
                "overall_severity": "none",
                "findings": [],
                "reviewed_sha": "sha",
                "limitations": "",
            }

        argv = [
            "manus_security_review.py",
            "--diff-file",
            str(self.diff_file),
            "--sha",
            "deadbeef",
            "--json-output",
            str(self.json_out),
            "--markdown-output",
            str(self.md_out),
        ] + (extra_argv or [])
        with mock.patch.dict(os.environ, env, clear=False), mock.patch.object(
            manus, "create_and_poll", side_effect=fake_review
        ):
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                with mock.patch.object(sys, "argv", argv):
                    code = manus.main()
        return code, calls

    def test_no_api_key_is_a_clean_skip(self):
        code, calls = self.run_main(make_diff({"a.dart": "a"}), extra_env={"MANUS_API_KEY": ""})
        self.assertEqual(code, 0)
        self.assertEqual(calls, [])

    def test_empty_diff_writes_an_empty_report(self):
        code, calls = self.run_main("\n")
        self.assertEqual(code, 0)
        self.assertEqual(calls, [])
        report = json.loads(self.json_out.read_text(encoding="utf-8"))
        self.assertEqual(report["overall_severity"], "none")

    def test_large_diff_is_reviewed_instead_of_failing(self):
        """Regression: PR #636's 4.75 MB diff used to abort the job."""
        files = {f"mobile/lib/screen_{index}.dart": "body" * 10 for index in range(1200)}
        diff = make_diff(files, context_lines=40)
        self.assertGreater(len(diff), 1_500_000, "the fixture must exceed the old 1.5 MB limit")
        code, calls = self.run_main(diff)
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), manus.DEFAULT_MAX_CHUNKS)
        report = json.loads(self.json_out.read_text(encoding="utf-8"))
        self.assertEqual(report["chunks_reviewed"], manus.DEFAULT_MAX_CHUNKS)
        self.assertGreater(len(report["excluded_files"]), 0)
        self.assertIn("Not reviewed", report["limitations"])
        markdown = self.md_out.read_text(encoding="utf-8")
        self.assertIn("## Review scope", markdown)

    def test_max_chunks_flag_is_honoured(self):
        files = {f"mobile/lib/screen_{index}.dart": "body" * 10 for index in range(300)}
        code, calls = self.run_main(make_diff(files, context_lines=40), extra_argv=["--max-chunks", "2"])
        self.assertEqual(code, 0)
        self.assertEqual(len(calls), 2)

    def test_findings_are_merged_and_deduplicated(self):
        finding = {
            "file": "lib/api.dart",
            "line": 12,
            "severity": "high",
            "confidence": "high",
            "category": "insecure transport",
            "title": "Cleartext HTTP",
            "evidence": "http://",
            "rationale": "no TLS",
            "remediation": "use https",
        }
        stub = {
            "summary": "ok",
            "overall_severity": "high",
            "findings": [dict(finding), dict(finding)],
            "reviewed_sha": "sha",
            "limitations": "",
        }
        files = {f"mobile/lib/screen_{index}.dart": "body" for index in range(20)}
        code, _ = self.run_main(make_diff(files), stub_reports=[stub])
        # MANUS_SECURITY_BLOCKING is not set, so an advisory finding must not fail the job.
        self.assertEqual(code, 0)
        report = json.loads(self.json_out.read_text(encoding="utf-8"))
        self.assertEqual(len(report["findings"]), 1)
        self.assertEqual(report["overall_severity"], "high")


class RedactionTest(unittest.TestCase):
    def test_credentials_are_redacted_in_diff_bodies(self):
        """Regression: unified-diff lines start with '+'/'-', so the old anchored
        pattern never matched and credentials reached the Manus API."""
        diff = (
            "diff --git a/config.dart b/config.dart\n"
            "--- a/config.dart\n"
            "+++ b/config.dart\n"
            "@@ -1,3 +1,3 @@\n"
            "+const api_key = 'sk-live-1234567890abcdef'\n"
            "-const password = \"hunter2-secret\"\n"
            " const token = 'refresh-abc123'\n"
        )
        redacted = manus.redact_diff(diff)
        self.assertNotIn("sk-live-1234567890abcdef", redacted)
        self.assertNotIn("hunter2-secret", redacted)
        self.assertIn("+const api_key = [REDACTED]", redacted)
        self.assertIn("-const password = [REDACTED]", redacted)

    def test_bearer_and_header_credentials_are_redacted(self):
        diff = "+headers['Authorization'] = 'Bearer abcdefghijklmnop1234567890'\n"
        redacted = manus.redact_diff(diff)
        self.assertNotIn("abcdefghijklmnop1234567890", redacted)
        self.assertIn("Bearer [REDACTED]", redacted)


if __name__ == "__main__":
    unittest.main()
