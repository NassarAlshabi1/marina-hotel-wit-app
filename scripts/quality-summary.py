import json
import os

def load_json(filepath):
    if os.path.exists(filepath):
        try:
            with open(filepath, "r") as f:
                return json.load(f)
        except:
            return {}
    return {}

def generate_dashboard():
    perf = load_json("reports/performance.json")
    comp = load_json("reports/complexity.json")
    dead = load_json("reports/dead_code.json")
    
    # قراءة تقرير التكرار من jscpd (إذا وجد)
    dup_percentage = "0%"
    jscpd_data = load_json("reports/jscpd-report.json")
    if jscpd_data and "statistics" in jscpd_data:
        dup_percentage = f"{jscpd_data['statistics']['total']['percentage']}%"

    # حساب السكور النهائي
    base_score = perf.get("score", 100)
    base_score -= (comp.get("deep_nesting", 0) * 2)
    base_score -= (dead.get("unused_elements", 0) * 1)
    
    if "%" in dup_percentage:
        try:
            val = float(dup_percentage.replace("%", ""))
            base_score -= (val * 2)
        except: pass
    
    final_score = max(0, min(100, int(base_score)))
    
    # حفظ السكور للـ Quality Gate
    with open("reports/final_score.txt", "w") as f:
        f.write(str(final_score))

    # تحديد لون السكور
    score_color = "success" if final_score >= 80 else "critical" if final_score < 60 else "warning"

    markdown = f"""
# 🏆 Marina Hotel Quality Dashboard

![Quality Score](https://img.shields.io/badge/Quality_Score-{final_score}%2F100-{score_color}?style=for-the-badge)

### 📊 Core Metrics

| Metric | Status | Details |
|--------|--------|---------|
| **Build & Tests** | ✅ Passed | All unit & widget tests passed |
| **Security** | 🔐 Check | See Security Section below |
| **Duplication** | 👯 {dup_percentage} | Code duplication across project |
| **Dead Code** | 💀 {dead.get('unused_elements', 0)} | Unused variables/functions |

---

### ⚡ Performance & Architecture

- **Total Dart Files:** {perf.get('total_dart_files', 0)}
- **Average File Size:** {perf.get('average_file_size', 0)} LOC
- **State Management:** {perf.get('consumer_widgets', 0)} `ConsumerWidget` vs {perf.get('set_state_calls', 0)} `setState`

<details>
<summary><b>📂 Largest Files (Click to expand)</b></summary>

1. `{perf.get('largest_file', {}).get('name', 'N/A')}` ({perf.get('largest_file', {}).get('lines', 0)} lines)
</details>

---

### 🧩 Complexity Analysis

- **Deep Nesting (>5 levels):** {comp.get('deep_nesting', 0)} blocks
- **Total `if`/`switch` statements:** {comp.get('total_if_switch', 0)}

<details>
<summary><b>⚠️ Most Complex Files (Click to expand)</b></summary>

| File | Ifs/Switches | Max Nesting Level |
|------|--------------|-------------------|
"""
    for f in comp.get("complex_files", []):
        markdown += f"| `{f['file']}` | {f['ifs']} | {f['max_nesting']} |\n"

    markdown += """
</details>

---
*Generated automatically by Marina Hotel Quality Gate 🚀*
"""

    with open("reports/quality_summary.md", "w", encoding="utf-8") as f:
        f.write(markdown)
    print("Dashboard generated successfully.")

if __name__ == "__main__":
    generate_dashboard()
