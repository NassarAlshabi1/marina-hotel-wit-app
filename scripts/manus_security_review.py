#!/usr/bin/env python3
"""Run a privacy-scoped Manus security review for a GitHub pull-request diff.

The script sends only the redacted unified diff and returns a strict JSON report.
Static scanners remain authoritative; Manus is an advisory review layer unless
MANUS_SECURITY_BLOCKING=true is explicitly configured in the workflow.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, NamedTuple

API_BASE = os.environ.get("MANUS_API_BASE", "https://api.manus.ai").rstrip("/")
POLL_SECONDS = 5
MAX_POLLS = 240
# ✅ 2026-08-31: خُفِّض من 12_000 إلى 5_000 حرف.
# الـ Manus API يحدّ "message content" بـ 5000 estimated tokens، والمحتوى
# العربي (تعليقات YAML/Dart) يستهلك توكنات أكثر من الإنجليزية (~2 حرف/توكن)،
# فجزء 12K حرف قد يتجاوز الحد ويفشل الطلب بـ HTTP 400 (run 33440645636).
# حدّ 5_000 حرف يبقى دائماً تحت سقف الـ API حتى مع نص عربي كثيف.
MAX_DIFF_CHUNK_CHARS = 5_000
# ✅ 2026-10-20: إصلاح فشل PR #636 (run 39314309799). الطلب غيّر 1490 ملفاً،
# فأنتج `git diff --unified=80` نصاً بحجم 4.75 MB، وكان السكربت يرمي خطأً فورياً
# عند تجاوز 1.5 MB فيفشل الـ Workflow قبل أي اتصال بالـ API. إرسال diff كامل
# مستحيل أصلاً (4.75 MB ≈ 950 قطعة متسلسلة تتجاوز timeout-minutes: 25)، لذلك
# تُراجَع أهم الملفات أمنياً ضمن ميزانية قطع محدودة، وتُذكَر الملفات غير
# المراجَعة صراحةً في التقرير بدلاً من إفشال الفحص الاستشاري.
DEFAULT_MAX_CHUNKS = 12
# حماية للـ runner فقط (قراءة diff هائل في الذاكرة)؛ ليست سبب فشل للمراجعة.
MAX_DIFF_BYTES = 25_000_000

# أولوية الملفات للمراجعة الأمنية: الأعلى يُراجَع أولاً داخل الميزانية.
SECURITY_PATH_WEIGHTS: tuple[tuple[str, int], ...] = (
    (r"^\.github/workflows/", 100),
    (r"^(?:scripts|tools|bin|\.github)/", 90),
    (r"\.php$", 80),
    (r"(?:auth|login|token|credential|password|secret|session|crypto|encrypt|payment)", 75),
    (r"(?:api|http|network|client|sync|backup|upload|import|export)", 70),
    (r"(?:database|drift|migrat|sqflite|sqlite|repository|local_db)", 65),
    (r"\.(?:ts|js|mjs|cjs)$", 60),
    (r"\.dart$", 50),
    (r"\.(?:yml|yaml)$", 40),
)
# مكافأة إضافية عند وجود أنماط حساسة داخل القطعة نفسها.
CONTENT_BONUS = 25
CONTENT_PATTERN = re.compile(
    r"(?i)(?:api[_-]?key|secret|password|passwd|token|bearer\s|private[_-]?key|http://|"
    r"eval\(|process\.run|runtime\.getruntime|rawquery|rawinsert|\.exec\(|"
    r"allowarbitraryloads|setjavascriptmode|loadrequest|unserialize|pickle\.loads|"
    r"file_get_contents|include_once|require_once|\$_(?:GET|POST|REQUEST))"
)
DEFAULT_WEIGHT = 30

SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "summary": {"type": "string"},
        "overall_severity": {
            "type": "string",
            "enum": ["none", "low", "medium", "high", "critical"],
        },
        "findings": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "file": {"type": "string"},
                    "line": {"type": "integer"},
                    "severity": {
                        "type": "string",
                        "enum": ["low", "medium", "high", "critical"],
                    },
                    "confidence": {
                        "type": "string",
                        "enum": ["low", "medium", "high"],
                    },
                    "category": {"type": "string"},
                    "title": {"type": "string"},
                    "evidence": {"type": "string"},
                    "rationale": {"type": "string"},
                    "remediation": {"type": "string"},
                },
                "required": [
                    "file",
                    "line",
                    "severity",
                    "confidence",
                    "category",
                    "title",
                    "evidence",
                    "rationale",
                    "remediation",
                ],
                "additionalProperties": False,
            },
        },
        "reviewed_sha": {"type": "string"},
        "limitations": {"type": "string"},
    },
    "required": [
        "summary",
        "overall_severity",
        "findings",
        "reviewed_sha",
        "limitations",
    ],
    "additionalProperties": False,
}


def request_json(method: str, url: str, api_key: str, payload: Any = None) -> dict[str, Any]:
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Accept": "application/json",
            "Content-Type": "application/json",
            "x-manus-api-key": api_key,
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")[:1000]
        raise RuntimeError(f"Manus API HTTP {error.code}: {detail}") from error
    except urllib.error.URLError as error:
        raise RuntimeError(f"Manus API connection failed: {error.reason}") from error
    if not isinstance(body, dict):
        raise RuntimeError("Manus API returned a non-object response")
    if body.get("ok") is False:
        error = body.get("error") or {}
        raise RuntimeError(f"Manus API error: {error.get('code', 'unknown')}: {error.get('message', 'unknown error')}")
    return body


def redact_diff(diff: str) -> str:
    """Remove common credential values while preserving file/line context."""
    import re

    patterns = [
        # ✅ 2026-10-20: every body line of a unified diff starts with '+', '-', or
        # a space, and the assignment usually sits behind a qualifier (`const`,
        # `static`, `$`, YAML indentation), so the previous '^(\s*key\s*[:=])'
        # anchor never matched diff content and credentials were sent to the API
        # unredacted. Allow a diff prefix plus arbitrary leading text on the line.
        r"(?im)^([+\- ]?[^#\n]*?\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|private[_-]?key)\s*[:=]\s*)([^\s#]+)",
        r"(?i)(Bearer\s+)[A-Za-z0-9._~+/=-]{16,}",
        r"(?i)(x-api-key\s*[:=]\s*)[^\s,;]+",
    ]
    result = diff
    for pattern in patterns:
        result = re.sub(pattern, r"\1[REDACTED]", result)
    return result


def extract_result(events: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, str | None]:
    latest_error: str | None = None
    for event in events:
        if event.get("type") == "error_message":
            latest_error = str(event.get("error_message") or event.get("message") or "Manus task error")
        if event.get("type") == "structured_output_result":
            result = event.get("structured_output_result") or {}
            if result.get("success") is True and isinstance(result.get("value"), dict):
                return result["value"], None
            latest_error = str(result.get("error") or "Structured output extraction failed")
    return None, latest_error


def create_and_poll(api_key: str, prompt: str) -> dict[str, Any]:
    created = request_json(
        "POST",
        f"{API_BASE}/v2/task.create",
        api_key,
        {
            "message": {"content": prompt},
            "title": "Marina Hotel pull-request security review",
            "locale": "en",
            "interactive_mode": False,
            "hide_in_task_list": True,
            "share_visibility": "private",
            "agent_profile": "manus-1.6-lite",
            "structured_output_schema": SCHEMA,
        },
    )
    task_id = created.get("task_id")
    if not isinstance(task_id, str) or not task_id:
        raise RuntimeError("Manus task.create response did not contain task_id")

    not_found_attempts = 0
    for _ in range(MAX_POLLS):
        query = urllib.parse.urlencode(
            {"task_id": task_id, "order": "asc", "limit": "100", "verbose": "false"}
        )
        try:
            messages = request_json("GET", f"{API_BASE}/v2/task.listMessages?{query}", api_key)
            not_found_attempts = 0
        except RuntimeError as error:
            # Manus creates tasks asynchronously. A first listMessages call can
            # briefly return 404 before the task is visible to the same key.
            message = str(error).lower()
            if "http 404" not in message or "task not found" not in message:
                raise
            not_found_attempts += 1
            if not_found_attempts > 12:
                raise RuntimeError(
                    "Manus task remained unavailable after 12 retries; "
                    "verify the API key belongs to the same Manus account and has task access."
                ) from error
            time.sleep(min(2 ** min(not_found_attempts, 5), 30))
            continue
        events = messages.get("data") or messages.get("messages") or []
        if not isinstance(events, list):
            raise RuntimeError("Manus task.listMessages returned an invalid event list")
        result, error = extract_result([event for event in events if isinstance(event, dict)])
        if result is not None:
            return result
        if error:
            raise RuntimeError(error)
        status = ""
        for event in events:
            if isinstance(event, dict) and event.get("type") == "status_update":
                update = event.get("status_update") or {}
                status = str(update.get("status") or "")
        if status == "error":
            raise RuntimeError("Manus task ended with status error")
        time.sleep(POLL_SECONDS)
    raise TimeoutError("Manus security review exceeded the polling timeout")


def split_sections(diff: str) -> list[str]:
    """Split a unified diff into one section per changed file."""
    sections = re.split(r"(?=^diff --git )", diff, flags=re.MULTILINE)
    return [section for section in sections if section.strip()]


def split_oversized(section: str, max_chars: int = MAX_DIFF_CHUNK_CHARS) -> list[str]:
    """Split a single file diff that is itself larger than one chunk.

    A single file diff can exceed the limit; split on lines while preserving
    the section content rather than silently dropping it.
    """
    if len(section) <= max_chars:
        return [section]
    # A single minified or generated line can exceed the limit on its own; slice
    # it by characters first so no piece can overflow the API message limit.
    lines: list[str] = []
    for line in section.splitlines(keepends=True):
        while len(line) > max_chars:
            lines.append(line[:max_chars])
            line = line[max_chars:]
        if line:
            lines.append(line)
    parts: list[str] = []
    part = ""
    for line in lines:
        if part and len(part) + len(line) > max_chars:
            parts.append(part)
            part = ""
        part += line
    if part:
        parts.append(part)
    return parts


def pack_pieces(pieces: list[str], max_chars: int = MAX_DIFF_CHUNK_CHARS) -> list[str]:
    """Pack diff pieces into chunks that stay below the Manus message limit."""
    chunks: list[str] = []
    current = ""
    for piece in pieces:
        if current and len(current) + len(piece) > max_chars:
            chunks.append(current)
            current = ""
        current += piece
    if current:
        chunks.append(current)
    return chunks


def split_diff(diff: str, max_chars: int = MAX_DIFF_CHUNK_CHARS) -> list[str]:
    """Split a unified diff into reviewable chunks below Manus' token limit."""
    pieces: list[str] = []
    for section in split_sections(diff):
        pieces.extend(split_oversized(section, max_chars))
    return pack_pieces(pieces, max_chars)


def section_path(section: str) -> str:
    """Return the file path a diff section belongs to."""
    match = re.search(r"^\+\+\+ (?:b/)?(\S+)", section, flags=re.MULTILINE)
    if match and match.group(1) != "/dev/null":
        return match.group(1)
    match = re.search(r"^diff --git a/.+ b/(.+)$", section, flags=re.MULTILINE)
    if match:
        return match.group(1)
    return "<unknown>"


def section_weight(section: str) -> int:
    """Rank a diff section so security-relevant files are reviewed first."""
    path = section_path(section)
    weight = DEFAULT_WEIGHT
    for pattern, value in SECURITY_PATH_WEIGHTS:
        if re.search(pattern, path, flags=re.IGNORECASE):
            weight = max(weight, value)
    if CONTENT_PATTERN.search(section):
        weight += CONTENT_BONUS
    return weight


class ReviewPlan(NamedTuple):
    """What the review will send to Manus and what it had to leave out."""

    chunks: list[str]
    reviewed: list[str]
    excluded: list[str]
    total_sections: int


def plan_review(diff: str, max_chunks: int = DEFAULT_MAX_CHUNKS) -> ReviewPlan:
    """Select the highest-priority diff sections that fit the chunk budget.

    Every Manus chunk is a separate task polled to completion, so the review is
    bounded by ``max_chunks`` instead of failing on large pull requests. Files
    that do not fit are reported as excluded so the summary never overstates
    the coverage of an advisory review.
    """
    if max_chunks < 1:
        raise ValueError("max_chunks must be at least 1")
    sections = split_sections(diff)
    ordered = sorted(sections, key=lambda section: (-section_weight(section), len(section), section_path(section)))
    budget = max_chunks * MAX_DIFF_CHUNK_CHARS
    pieces: list[str] = []
    reviewed: list[str] = []
    excluded: list[str] = []
    used = 0
    for section in ordered:
        if used + len(section) <= budget:
            pieces.extend(split_oversized(section))
            reviewed.append(section_path(section))
            used += len(section)
        else:
            # Keep scanning: a smaller high-priority file can still fit after a
            # large one was skipped.
            excluded.append(section_path(section))
    # total selected chars <= budget, so packing cannot exceed max_chunks.
    chunks = pack_pieces(pieces)[:max_chunks]
    return ReviewPlan(chunks=chunks, reviewed=reviewed, excluded=excluded, total_sections=len(sections))


def _env_max_chunks() -> int:
    """Read the optional MANUS_MAX_CHUNKS override used by the workflow."""
    raw = os.environ.get("MANUS_MAX_CHUNKS", "").strip()
    if not raw:
        return DEFAULT_MAX_CHUNKS
    try:
        return max(1, int(raw))
    except ValueError:
        print(f"Ignoring invalid MANUS_MAX_CHUNKS={raw!r}; using {DEFAULT_MAX_CHUNKS}.", file=sys.stderr)
        return DEFAULT_MAX_CHUNKS



def review_chunk_prompt(sha: str, chunk: str, index: int, total: int) -> str:
    return f"""You are Manus performing security code review chunk {index} of {total} for a Flutter/Dart hotel-management application.
Review only vulnerabilities introduced by the supplied unified-diff chunk. Do not treat style, complexity, duplication, or ordinary test changes as security findings.
Do not invent missing context. A finding must include concrete evidence from an added or modified line in this chunk and a practical remediation.
Prioritize credential exposure, injection, insecure transport, authorization/authentication bypass, unsafe deserialization, path traversal, command execution, sensitive-data leakage, and workflow supply-chain risks.
Return the required structured result even when there are no findings. The final review is advisory; do not mark ordinary quality issues as vulnerabilities.
The reviewed commit SHA is: {sha}

Unified diff chunk (credentials are redacted before transmission):
--- BEGIN DIFF CHUNK ---
{chunk}
--- END DIFF CHUNK ---
"""


def _line_for_deduplication(value: Any) -> int:
    """Return a stable integer line for finding deduplication.

    The structured response asks Manus for an integer, but malformed or
    partially recovered responses must not abort the complete security report.
    Invalid values intentionally share the neutral line ``0`` for deduplication
    while the original finding remains unchanged in the emitted report.
    """
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            pass
    return 0


def review_scope_note(plan: ReviewPlan) -> str:
    """Describe exactly which files the review covered and which it skipped."""
    covered = (
        f"Covered {len(plan.reviewed)} of {plan.total_sections} changed source file(s) "
        f"in {len(plan.chunks)} diff chunk(s) under the {DEFAULT_MAX_CHUNKS}-chunk budget"
    )
    if not plan.excluded:
        return f"{covered}; no file was left out."
    shown = ", ".join(plan.excluded[:15])
    remaining = len(plan.excluded) - 15
    if remaining > 0:
        shown += f", … and {remaining} more"
    return f"{covered}. Not reviewed ({len(plan.excluded)}): {shown}."


def merge_reports(reports: list[dict[str, Any]], sha: str, plan: ReviewPlan) -> dict[str, Any]:
    severity_rank = {"none": 0, "low": 1, "medium": 2, "high": 3, "critical": 4}
    findings: list[dict[str, Any]] = []
    seen: set[tuple[str, int, str]] = set()
    for report in reports:
        for finding in report.get("findings", []):
            if not isinstance(finding, dict):
                continue
            key = (
                str(finding.get("file", "")),
                _line_for_deduplication(finding.get("line", 0)),
                str(finding.get("title", "")),
            )
            if key not in seen:
                seen.add(key)
                findings.append(finding)
    overall = "none"
    for finding in findings:
        level = str(finding.get("severity", "low"))
        if severity_rank.get(level, 0) > severity_rank[overall]:
            overall = level
    total_chunks = len(plan.chunks)
    if findings:
        summary = (
            f"Manus reviewed {len(plan.reviewed)} of {plan.total_sections} changed file(s) "
            f"across {total_chunks} diff chunk(s) and returned {len(findings)} finding(s)."
        )
    else:
        summary = (
            f"Manus reviewed {len(plan.reviewed)} of {plan.total_sections} changed file(s) "
            f"across {total_chunks} diff chunk(s) and identified no concrete security vulnerabilities."
        )
    return {
        "summary": summary,
        "overall_severity": overall,
        "findings": findings,
        "reviewed_sha": sha,
        "reviewed_files": plan.reviewed,
        "excluded_files": plan.excluded,
        "chunks_reviewed": total_chunks,
        "limitations": (
            f"{review_scope_note(plan)} Manus API limits message content size, so the diff is "
            "split into chunks and the most security-relevant files are prioritised. Findings "
            "are advisory and limited to the reviewed diff; the static scanners stay authoritative."
        ),
    }


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# Manus Security Review",
        "",
        f"**Overall severity:** `{report.get('overall_severity', 'unknown')}`",
        "",
        report.get("summary", "No summary returned."),
        "",
    ]
    excluded = report.get("excluded_files") or []
    reviewed = report.get("reviewed_files") or []
    if reviewed or excluded:
        lines.extend(
            [
                "## Review scope",
                "",
                f"- Reviewed files: {len(reviewed)}",
                f"- Files not reviewed (outside the chunk budget): {len(excluded)}",
                "",
            ]
        )
    lines.extend(["## Findings", ""])
    findings = report.get("findings") or []
    if not findings:
        lines.append("No findings were returned for the reviewed diff.")
    else:
        for index, finding in enumerate(findings, 1):
            lines.extend(
                [
                    f"### {index}. {finding.get('title', 'Untitled finding')}",
                    "",
                    f"- **Location:** `{finding.get('file', '?')}:{finding.get('line', 0)}`",
                    f"- **Severity:** `{finding.get('severity', '?')}`; confidence: `{finding.get('confidence', '?')}`",
                    f"- **Category:** {finding.get('category', '')}",
                    f"- **Evidence:** {finding.get('evidence', '')}",
                    f"- **Rationale:** {finding.get('rationale', '')}",
                    f"- **Remediation:** {finding.get('remediation', '')}",
                    "",
                ]
            )
    lines.extend(["## Limitations", "", report.get("limitations", "")])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--diff-file", required=True, type=Path)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--json-output", type=Path, default=Path("manus-security-report.json"))
    parser.add_argument("--markdown-output", type=Path, default=Path("manus-security-report.md"))
    parser.add_argument(
        "--max-chunks",
        type=int,
        default=_env_max_chunks(),
        help=(
            "Maximum number of Manus chunks (one task each) to review. Defaults to "
            f"MANUS_MAX_CHUNKS or {DEFAULT_MAX_CHUNKS}. Files that do not fit are reported "
            "as not reviewed instead of failing the advisory check."
        ),
    )
    args = parser.parse_args()
    if args.max_chunks < 1:
        parser.error("--max-chunks must be at least 1")

    api_key = os.environ.get("MANUS_API_KEY", "")
    if not api_key:
        print("MANUS_API_KEY is not configured; Manus review was skipped.", file=sys.stderr)
        return 0

    diff = redact_diff(args.diff_file.read_text(encoding="utf-8", errors="replace"))
    diff_bytes = len(diff.encode("utf-8"))
    if not diff.strip() or diff_bytes > MAX_DIFF_BYTES:
        if diff.strip():
            print(
                f"Redacted diff is {diff_bytes} bytes, above the {MAX_DIFF_BYTES}-byte runner "
                "guard; no chunk was sent to Manus.",
                file=sys.stderr,
            )
            report = {
                "summary": "The redacted diff was too large to read into the review runner.",
                "overall_severity": "none",
                "findings": [],
                "reviewed_sha": args.sha,
                "reviewed_files": [],
                "excluded_files": [],
                "chunks_reviewed": 0,
                "limitations": (
                    f"The redacted diff ({diff_bytes} bytes) exceeded the {MAX_DIFF_BYTES}-byte "
                    "runner guard, so this advisory review covered nothing. The static scanners "
                    "remain authoritative."
                ),
            }
        else:
            report = {
                "summary": "No reviewable source or workflow diff was found for this commit.",
                "overall_severity": "none",
                "findings": [],
                "reviewed_sha": args.sha,
                "reviewed_files": [],
                "excluded_files": [],
                "chunks_reviewed": 0,
                "limitations": (
                    "The configured review scope sends only Dart, PHP, JS/TS, and YAML changes to "
                    "Manus; other file types are never transmitted."
                ),
            }
        args.json_output.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        write_markdown(report, args.markdown_output)
        print(report["summary"])
        return 0

    plan = plan_review(diff, args.max_chunks)
    print(
        f"Redacted diff: {diff_bytes} bytes across {plan.total_sections} file(s); "
        f"reviewing {len(plan.reviewed)} file(s) in {len(plan.chunks)} chunk(s), "
        f"{len(plan.excluded)} file(s) reported as not reviewed.",
        file=sys.stderr,
    )
    reports: list[dict[str, Any]] = []
    for index, chunk in enumerate(plan.chunks, 1):
        prompt = review_chunk_prompt(args.sha, chunk, index, len(plan.chunks))
        reports.append(create_and_poll(api_key, prompt))
    report = merge_reports(reports, args.sha, plan)
    args.json_output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    write_markdown(report, args.markdown_output)
    print(json.dumps(report, ensure_ascii=False))

    blocking = any(
        finding.get("severity") in {"high", "critical"} and finding.get("confidence") == "high"
        for finding in report.get("findings", [])
        if isinstance(finding, dict)
    )
    return 2 if blocking and os.environ.get("MANUS_SECURITY_BLOCKING", "false").lower() == "true" else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:  # pragma: no cover - CI boundary
        print(f"Manus security review failed: {error}", file=sys.stderr)
        raise SystemExit(1)
