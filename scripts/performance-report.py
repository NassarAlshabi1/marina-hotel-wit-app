import os
import re
import json

def analyze_performance(directory="lib"):
    stats = {
        "total_dart_files": 0,
        "total_lines": 0,
        "stateful_widgets": 0,
        "consumer_widgets": 0,
        "set_state_calls": 0,
        "future_builders": 0,
        "stream_builders": 0,
        "files_over_500": 0,
        "files_over_1000": 0,
        "largest_file": {"name": "", "lines": 0}
    }

    for root, _, files in os.walk(directory):
        for file in files:
            if file.endswith(".dart") and not any(ext in file for ext in [".g.dart", ".freezed.dart", ".config.dart"]):
                filepath = os.path.join(root, file)
                stats["total_dart_files"] += 1
                
                try:
                    with open(filepath, 'r', encoding='utf-8') as f:
                        lines = f.readlines()
                        line_count = len(lines)
                        content = "".join(lines)
                        
                        stats["total_lines"] += line_count
                        
                        if line_count > 1000:
                            stats["files_over_1000"] += 1
                        elif line_count > 500:
                            stats["files_over_500"] += 1
                            
                        if line_count > stats["largest_file"]["lines"]:
                            stats["largest_file"] = {"name": file, "lines": line_count}

                        stats["stateful_widgets"] += len(re.findall(r'extends\s+StatefulWidget', content))
                        stats["consumer_widgets"] += len(re.findall(r'extends\s+(ConsumerWidget|ConsumerStatefulWidget)', content))
                        stats["set_state_calls"] += len(re.findall(r'setState\s*\(', content))
                        stats["future_builders"] += len(re.findall(r'FutureBuilder', content))
                        stats["stream_builders"] += len(re.findall(r'StreamBuilder', content))
                except Exception as e:
                    print(f"Error reading {filepath}: {e}")

    stats["average_file_size"] = stats["total_lines"] // stats["total_dart_files"] if stats["total_dart_files"] > 0 else 0
    
    # حساب سكور تقريبي (يبدأ من 100 ويقل مع الممارسات السيئة)
    score = 100
    score -= (stats["files_over_1000"] * 5)
    score -= (stats["files_over_500"] * 2)
    score -= (stats["set_state_calls"] * 0.5) # تشجيع استخدام Riverpod بدلاً من setState
    stats["score"] = max(0, int(score))

    if not os.path.exists("reports"):
        os.makedirs("reports")
        
    with open("reports/performance.json", "w") as f:
        json.dump(stats, f, indent=4)

if __name__ == "__main__":
    analyze_performance()
