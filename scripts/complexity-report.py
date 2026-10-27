import os
import re
import json

import sys
def analyze_complexity(directory=None):
    if directory is None:
        directory = sys.argv[1] if len(sys.argv) > 1 else "lib"
    stats = {
        "complex_files": [],
        "long_functions": 0,
        "deep_nesting": 0,
        "total_if_switch": 0
    }

    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".dart") and not any(ext in file for ext in [".g.dart", ".freezed.dart"]):
                filepath = os.path.join(root, file)
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        content = f.read()
                        lines = content.split('\n')
                        
                        # حساب الـ if و switch
                        ifs = len(re.findall(r'\bif\s*\(', content))
                        switches = len(re.findall(r'\bswitch\s*\(', content))
                        stats["total_if_switch"] += (ifs + switches)

                        # حساب التعشيق (Nesting)
                        max_nesting = 0
                        current_nesting = 0
                        
                        for line in lines:
                            clean_line = line.strip()
                            if clean_line.startswith('//'): continue
                            
                            # تتبع الأقواس للتعشيق
                            current_nesting += clean_line.count('{')
                            current_nesting -= clean_line.count('}')
                            if current_nesting > max_nesting:
                                max_nesting = current_nesting
                                
                            if current_nesting > 5:
                                stats["deep_nesting"] += 1

                        if max_nesting > 5 or ifs > 15 or len(lines) > 500:
                            stats["complex_files"].append({
                                "file": file,
                                "ifs": ifs,
                                "max_nesting": max_nesting,
                                "lines": len(lines)
                            })
                except Exception as e:
                    print(f"Error reading {filepath}: {e}")

    # ترتيب الملفات المعقدة
    stats["complex_files"] = sorted(stats["complex_files"], key=lambda x: x['max_nesting'], reverse=True)[:5]

    if not os.path.exists("reports"):
        os.makedirs("reports")

    with open("reports/complexity.json", "w") as f:
        json.dump(stats, f, indent=4)

if __name__ == "__main__":
    analyze_complexity()
