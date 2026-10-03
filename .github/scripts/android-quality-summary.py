"""Report actual findings, not a fabricated 0..100 code-quality score."""
from collections import Counter
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

reports = {
    "android_lint": (Path("mobile/build/app/reports/lint-results-debug.xml"), ".//issue"),
    "detekt": (Path("mobile/build/app/reports/detekt/detekt.xml"), ".//error"),
}
results = {}
diagnostics = {}

def annotation(title, text):
    # Static source diagnostics only: no snippets, environment or runtime data.
    escaped = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    print(f"::notice title={title}::{escaped}")

def relative_name(name):
    marker = "mobile/android/"
    return marker + name.split(marker, 1)[1] if marker in name else name

for tool, (path, query) in reports.items():
    if not path.exists():
        results[tool] = {"status": "report_not_generated", "findings": None}
        continue
    root = ET.parse(path).getroot()
    findings = root.findall(query)
    records = []
    if tool == "detekt":
        for file in root.findall("file"):
            for issue in file.findall("error"):
                records.append({"file": relative_name(file.get("name", "")),
                    "line": issue.get("line", ""), "rule": issue.get("source", ""),
                    "severity": issue.get("severity", ""), "message": issue.get("message", "")[:400]})
    else:
        for issue in findings:
            location = issue.find("location")
            records.append({"file": relative_name(location.get("file", "")) if location is not None else "",
                "line": location.get("line", "") if location is not None else "",
                "rule": issue.get("id", ""), "severity": issue.get("severity", ""),
                "message": issue.get("message", "")[:400]})
    diagnostics[tool] = records
    annotation(f"{tool} rules", json.dumps(Counter(r["rule"] for r in records), ensure_ascii=False))
    # Keep diagnostics accessible via GitHub's annotations API as well as the
    # artifact. Some review environments cannot reach the artifact blob host.
    chunk = []
    size = 0
    index = 1
    for record in records:
        line = json.dumps(record, ensure_ascii=False)
        if size + len(line) > 24000 and chunk:
            annotation(f"{tool} details {index}", "\n".join(chunk))
            index += 1
            chunk, size = [], 0
        chunk.append(line)
        size += len(line) + 1
    if chunk:
        annotation(f"{tool} details {index}", "\n".join(chunk))
    results[tool] = {"status": "measured", "findings": len(findings)}
    print(f"::notice title={tool} findings::{len(findings)} reported findings (see artifact)")
output = Path("quality-evidence")
output.mkdir(exist_ok=True)
(output / "diagnostics.json").write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2))
(output / "summary.json").write_text(json.dumps(results, indent=2))
if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(summary, "a") as handle:
        handle.write("## Android code-quality findings\n```json\n" + json.dumps(results, indent=2) + "\n```\n")
print(json.dumps(results, indent=2))
