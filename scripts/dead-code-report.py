import json
import os

def parse_dead_code():
    dead_code_stats = {
        "unused_files": 0,
        "unused_elements": 0,
        "unused_imports": 0,
        "details": []
    }

    # قراءة مخرجات flutter analyze
    analyze_file = "analyze_report.txt"
    if os.path.exists(analyze_file):
        try:
            with open(analyze_file, "r", encoding="utf-8") as f:
                lines = f.readlines()
                for line in lines:
                    if "unused_element" in line or "unused_field" in line or "unused_local_variable" in line:
                        dead_code_stats["unused_elements"] += 1
                        dead_code_stats["details"].append(line.strip())
                    elif "unused_import" in line:
                        dead_code_stats["unused_imports"] += 1
        except Exception as e:
            print(f"Error reading {analyze_file}: {e}")

    if not os.path.exists("reports"):
        os.makedirs("reports")

    with open("reports/dead_code.json", "w") as f:
        json.dump(dead_code_stats, f, indent=4)

if __name__ == "__main__":
    parse_dead_code()
