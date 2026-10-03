"""Report actual findings, not a fabricated 0..100 code-quality score."""
from collections import Counter
import base64
import gzip
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
    results[tool] = {"status": "measured", "findings": len(findings)}

# GitHub truncates annotation messages and caps notices per step. Carry compact
# file/rule tables plus coordinates rather than truncating actionable locations.
files = sorted({r["file"] for values in diagnostics.values() for r in values})
rules = sorted({r["rule"] for values in diagnostics.values() for r in values})
bundle = {"files": files, "rules": rules,
          "detekt": [[files.index(r["file"]), r["line"], rules.index(r["rule"])]
                     for r in diagnostics.get("detekt", [])],
          "lint": diagnostics.get("android_lint", [])}
encoded = base64.b64encode(gzip.compress(json.dumps(bundle, ensure_ascii=False).encode())).decode()
parts = [encoded[i:i + 3000] for i in range(0, len(encoded), 3000)]
for i, part in enumerate(parts, 1):
    annotation(f"Diagnostic bundle {i}/{len(parts)} (gzip base64)", part)
for tool, values in diagnostics.items():
    annotation(f"{tool} rules", json.dumps(Counter(r["rule"] for r in values)))
output = Path("quality-evidence")
output.mkdir(exist_ok=True)
(output / "diagnostics.json").write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2))
(output / "summary.json").write_text(json.dumps(results, indent=2))
if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(summary, "a") as handle:
        handle.write("## Android code-quality findings\n```json\n" + json.dumps(results, indent=2) + "\n```\n")
print(json.dumps(results, indent=2))
