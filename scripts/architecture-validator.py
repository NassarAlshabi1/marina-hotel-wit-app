#!/usr/bin/env python3
"""
architecture-validator.py
==========================

سكريبت التحقق من الالتزام بـ Clean Architecture + Riverpod في مشروع Marina Hotel.

القواعد المُتحقّقة:
1. منع استيراد طبقة UI (screens, widgets, components) من طبقة البيانات (services, repositories, data)
2. منع استيراد services مباشرة من screens (يجب المرور عبر providers)
3. منع الاعتماد الدائري بين الوحدات (circular dependency detection)
4. التزام Riverpod: screens تستخدم ConsumerStatefulWidget/ConsumerWidget
5. منع الوصول المباشر إلى قاعدة البيانات (local_db) من واجهة المستخدم

Usage:
    python3 architecture-validator.py --project-root /path/to/mobile

Exit codes:
    0 = كل القواعد مُحترمة
    1 = يوجد انتهاكات
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple


# ═══════════════════════════════════════════════════════════════
#  تعريف الطبقات (Layers)
# ═══════════════════════════════════════════════════════════════

LAYER_UI = {'screens', 'widgets', 'components'}
LAYER_STATE = {'providers'}
LAYER_DOMAIN = {'models', 'core', 'utils', 'mixins'}
LAYER_DATA = {'services', 'repositories', 'data', 'tasks'}
LAYER_DB = {'services/local_db.dart', 'services/local_db.g.dart'}

# قاعدة الاستيراد: كل طبقة يمكنها الاستيراد من الطبقات الأدنى فقط
# UI → State → Domain → Data → DB
LAYER_ORDER = {
    'ui': 0,
    'state': 1,
    'domain': 2,
    'data': 3,
    'db': 4,
}


def get_layer(file_path: str) -> str:
    """تحديد طبقة الملف بناءً على مساره."""
    if any(p in file_path for p in LAYER_DB):
        return 'db'
    parts = file_path.split('/')
    for part in parts:
        if part in LAYER_UI:
            return 'ui'
        if part in LAYER_STATE:
            return 'state'
        if part in LAYER_DATA:
            return 'data'
        if part in LAYER_DOMAIN:
            return 'domain'
    return 'unknown'


def get_imports(file_content: str) -> List[str]:
    """استخراج كل الاستيرادات من محتوى الملف."""
    pattern = r"^\s*import\s+['\"]([^'\"]+)['\"]"
    return re.findall(pattern, file_content, re.MULTILINE)


def resolve_import(imp: str, current_file: str, lib_root: Path) -> str:
    """تحويل استيراد نسبي أو package إلى مسار ملف فعلي."""
    # package: imports
    if imp.startswith('package:marina_hotel_mobile/'):
        relative = imp.replace('package:marina_hotel_mobile/', '')
        return str(lib_root / relative)
    # relative imports
    if imp.startswith('.'):
        current_dir = Path(current_file).parent
        resolved = (current_dir / imp).resolve()
        return str(resolved)
    return imp  # external package


def validate_no_ui_in_data(lib_root: Path) -> List[Tuple[str, str]]:
    """القاعدة 1: منع استيراد UI من Data layer."""
    violations = []
    for dart_file in lib_root.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        layer = get_layer(rel_path)
        if layer != 'data':
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        for imp in imports:
            resolved = resolve_import(imp, str(dart_file), lib_root)
            resolved_rel = resolved.replace(str(lib_root) + '/', '')
            imported_layer = get_layer(resolved_rel)
            if imported_layer == 'ui':
                violations.append((rel_path, imp))
    return violations


def validate_no_direct_db_from_ui(lib_root: Path) -> List[Tuple[str, str]]:
    """القاعدة 5: منع الوصول المباشر إلى قاعدة البيانات من UI."""
    violations = []
    for dart_file in lib_root.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        layer = get_layer(rel_path)
        if layer != 'ui':
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        for imp in imports:
            if 'local_db.dart' in imp or 'local_db.g.dart' in imp:
                violations.append((rel_path, imp))
    return violations


def validate_no_services_direct_from_ui(lib_root: Path) -> List[Tuple[str, str]]:
    """القاعدة 2: منع استيراد services مباشرة من screens (يجب المرور عبر providers)."""
    violations = []
    # استثناءات: بعض services مسموح بها من UI (مثل crashlytics, analytics, logging)
    allowed_services = {
        'crashlytics_service',
        'analytics_service',
        'logging',
        'app_logger',
    }
    for dart_file in (lib_root / 'screens').rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        for imp in imports:
            if 'services/' in imp:
                # تحقق من الاستثناءات
                if any(allowed in imp for allowed in allowed_services):
                    continue
                violations.append((rel_path, imp))
    return violations


def detect_circular_dependencies(lib_root: Path) -> List[Tuple[str, str]]:
    """القاعدة 3: كشف الاعتماد الدائري بين الوحدات (files)."""
    # بناء graph للاستيرادات
    graph: Dict[str, Set[str]] = {}
    for dart_file in lib_root.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        resolved_imports = set()
        for imp in imports:
            resolved = resolve_import(imp, str(dart_file), lib_root)
            if str(lib_root) in resolved:
                resolved_rel = resolved.replace(str(lib_root) + '/', '')
                resolved_imports.add(resolved_rel)
        graph[rel_path] = resolved_imports

    # DFS للكشف عن cycles
    cycles = []
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node: WHITE for node in graph}

    def dfs(node: str, path: List[str]) -> None:
        color[node] = GRAY
        path.append(node)
        for neighbor in graph.get(node, set()):
            if color.get(neighbor, WHITE) == GRAY:
                # cycle detected
                cycle_start = path.index(neighbor)
                cycle = path[cycle_start:] + [neighbor]
                cycles.append(tuple(cycle))
            elif color.get(neighbor, WHITE) == WHITE:
                dfs(neighbor, path)
        path.pop()
        color[node] = BLACK

    for node in graph:
        if color[node] == WHITE:
            dfs(node, [])

    return cycles[:5]  # أول 5 cycles فقط


def validate_riverpod_usage(lib_root: Path) -> List[Tuple[str, str]]:
    """القاعدة 4: التزام Riverpod — screens يجب أن تستخدم ConsumerWidget/ConsumerStatefulWidget."""
    violations = []
    screens_dir = lib_root / 'screens'
    if not screens_dir.exists():
        return violations

    for dart_file in screens_dir.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue

        # تخطّي الملفات غير الـ Widget (مثل models, helpers)
        if 'class ' not in content or 'Widget' not in content:
            continue

        # إذا كان الملف يُعرّف Widget لكن لا يستخدم ConsumerWidget
        has_stateful = 'StatefulWidget' in content
        has_stateless = 'StatelessWidget' in content
        has_consumer_stateful = 'ConsumerStatefulWidget' in content
        has_consumer_stateless = 'ConsumerWidget' in content

        if (has_stateful or has_stateless) and not (
            has_consumer_stateful or has_consumer_stateless
        ):
            violations.append((rel_path, 'يستخدم StatefulWidget/StatelessWidget بدلاً من ConsumerWidget'))

    return violations


def main() -> int:
    parser = argparse.ArgumentParser(description='Architecture Validator for Marina Hotel')
    parser.add_argument(
        '--project-root',
        required=True,
        help='Path to mobile/ directory (containing lib/)',
    )
    parser.add_argument(
        '--strict',
        action='store_true',
        help='Treat warnings as errors (exit 1 on any violation)',
    )
    args = parser.parse_args()

    lib_root = Path(args.project_root) / 'lib'
    if not lib_root.exists():
        print(f'❌ lib/ directory not found at {lib_root}')
        return 1

    print('═' * 60)
    print('  🏗️  Architecture Validator — Marina Hotel')
    print('═' * 60)
    print()

    all_violations = 0

    # القاعدة 1: منع UI في Data
    print('🔹 Rule 1: No UI imports in Data layer')
    violations = validate_no_ui_in_data(lib_root)
    if violations:
        print(f'   ❌ {len(violations)} violations:')
        for file, imp in violations[:10]:
            print(f'      {file} → {imp}')
        all_violations += len(violations)
    else:
        print('   ✅ Pass')
    print()

    # القاعدة 2: منع services مباشرة من UI
    print('🔹 Rule 2: No direct services imports from screens (use providers)')
    violations = validate_no_services_direct_from_ui(lib_root)
    if violations:
        print(f'   ⚠️  {len(violations)} violations (warning):')
        for file, imp in violations[:10]:
            print(f'      {file} → {imp}')
        if args.strict:
            all_violations += len(violations)
    else:
        print('   ✅ Pass')
    print()

    # القاعدة 3: كشف الاعتماد الدائري
    print('🔹 Rule 3: No circular dependencies')
    cycles = detect_circular_dependencies(lib_root)
    if cycles:
        print(f'   ❌ {len(cycles)} circular dependencies detected:')
        for cycle in cycles[:3]:
            print(f'      {" → ".join(cycle)}')
        all_violations += len(cycles)
    else:
        print('   ✅ Pass')
    print()

    # القاعدة 4: Riverpod
    print('🔹 Rule 4: Riverpod compliance (ConsumerWidget/ConsumerStatefulWidget)')
    violations = validate_riverpod_usage(lib_root)
    if violations:
        print(f'   ⚠️  {len(violations)} screens not using ConsumerWidget:')
        for file, msg in violations[:10]:
            print(f'      {file}: {msg}')
        if args.strict:
            all_violations += len(violations)
    else:
        print('   ✅ Pass')
    print()

    # القاعدة 5: منع DB مباشرة من UI
    print('🔹 Rule 5: No direct DB access from UI')
    violations = validate_no_direct_db_from_ui(lib_root)
    if violations:
        print(f'   ❌ {len(violations)} violations:')
        for file, imp in violations[:10]:
            print(f'      {file} → {imp}')
        all_violations += len(violations)
    else:
        print('   ✅ Pass')
    print()

    # النتيجة النهائية
    print('═' * 60)
    if all_violations == 0:
        print('  ✅ All architecture rules pass!')
        return 0
    else:
        print(f'  ❌ {all_violations} architecture violations found')
        return 1


if __name__ == '__main__':
    sys.exit(main())
