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
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

API_BASE = os.environ.get("MANUS_API_BASE", "https://api.manus.ai").rstrip("/")
POLL_SECONDS = 5
MAX_POLLS = 240

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
        r"(?im)^(\s*(?:export\s+)?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|password|passwd|secret|private[_-]?key)\s*[:=]\s*)([^\s#]+)",
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


def write_markdown(report: dict[str, Any], path: Path) -> None:
    lines = [
        "# Manus Security Review",
        "",
        f"**Overall severity:** `{report.get('overall_severity', 'unknown')}`",
        "",
        report.get("summary", "No summary returned."),
        "",
        "## Findings",
        "",
    ]
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
    args = parser.parse_args()

    api_key = os.environ.get("MANUS_API_KEY", "")
    if not api_key:
        print("MANUS_API_KEY is not configured; Manus review was skipped.", file=sys.stderr)
        return 0

    diff = redact_diff(args.diff_file.read_text(encoding="utf-8", errors="replace"))
    if not diff.strip():
        print("No reviewable diff found; Manus review was skipped.")
        return 0
    if len(diff.encode("utf-8")) > 1_500_000:
        raise RuntimeError("Redacted diff exceeds the configured 1.5 MB review limit")

    prompt = f"""You are Manus performing a security review of a pull-request diff for a Flutter/Dart hotel-management application.
Review only vulnerabilities introduced by the diff. Do not treat style, complexity, duplication, or ordinary test changes as security findings.
Do not invent missing context. A finding must include concrete evidence from an added or modified line and a practical remediation.
Prioritize credential exposure, injection, insecure transport, authorization/authentication bypass, unsafe deserialization, path traversal, command execution, sensitive-data leakage, and workflow supply-chain risks.
Return the required structured result even when there are no findings. Treat findings as blocking only when severity is high or critical AND confidence is high.
The reviewed commit SHA is: {args.sha}

Unified diff (credentials are redacted before transmission):
--- BEGIN DIFF ---
{diff}
--- END DIFF ---
"""
    report = create_and_poll(api_key, prompt)
    report["reviewed_sha"] = args.sha
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
