"""Report actual findings, not a fabricated 0..100 code-quality score."""
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

reports = {
    "android_lint": (Path("mobile/build/app/reports/lint-results-debug.xml"), ".//issue"),
    "detekt": (Path("mobile/build/app/reports/detekt/detekt.xml"), ".//error"),
}
results = {}
for tool, (path, query) in reports.items():
    if not path.exists():
        results[tool] = {"status": "report_not_generated", "findings": None}
        continue
    findings = ET.parse(path).findall(query)
    results[tool] = {"status": "measured", "findings": len(findings)}
    print(f"::notice title={tool} findings::{len(findings)} reported findings (see artifact)")
output = Path("quality-evidence")
output.mkdir(exist_ok=True)
(output / "summary.json").write_text(json.dumps(results, indent=2))
if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(summary, "a") as handle:
        handle.write("## Android code-quality findings\n```json\n" + json.dumps(results, indent=2) + "\n```\n")
print(json.dumps(results, indent=2))
