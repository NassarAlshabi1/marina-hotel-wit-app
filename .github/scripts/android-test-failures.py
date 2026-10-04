#!/usr/bin/env python3
"""Expose bounded JUnit failure details when artifact downloads are unavailable."""
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[2]
reports = root / "mobile/build/app/test-results/testDebugUnitTest"
count = 0
for path in sorted(reports.glob("TEST-*.xml")):
    for case in ET.parse(path).getroot().iter("testcase"):
        for failure in list(case.findall("failure")) + list(case.findall("error")):
            count += 1
            if count <= 6:
                text = f"{case.get('classname')}#{case.get('name')}: {failure.get('message', '')}"
                text = text[:2500].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
                print(f"::error title=JUnit failure {count}::{text}")
print(f"JUnit failures found in available XML reports: {count}")
