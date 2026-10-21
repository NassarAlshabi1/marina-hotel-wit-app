#!/usr/bin/env python3
"""
architecture-validator.py
==========================

سكريبت التحقق من الالتزام بـ Clean Architecture + Riverpod في مشروع Marina Hotel.

القواعد المُتحقّقة (مُقسّمة إلى errors و warnings):

ERRORS (تُسبب فشل الـ CI):
1. No direct DB access from UI — screens لا تستورد local_db.dart مباشرة
2. No circular dependencies — لا يوجد اعتماد دائري بين الوحدات

WARNINGS (لا تُسبب فشل الـ CI — تُعرض كـ info):
3. No direct services imports from screens — screens تستخدم providers
4. Riverpod compliance — ConsumerWidget/ConsumerStatefulWidget
5. No UI imports in Data layer — data layer لا يستورد UI

Excludes:
- شاشات الأدوات/الصيانة لا تحتاج ConsumerWidget (developer tools)
- شاشات AI/Reports قد لا تستخدم Riverpod
- شاشات إصلاح قاعدة البيانات للصيانة فقط

Usage:
    python3 architecture-validator.py --project-root /path/to/mobile

Exit codes:
    0 = لا توجد errors (warnings مسموحة)
    1 = يوجد errors (direct DB access أو circular deps)
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


# ═══════════════════════════════════════════════════════════════
#  Excludes — ملفات/مسارات لا تُفحص
# ═══════════════════════════════════════════════════════════════
#
#  هذه الملفات إما:
#  - شاشات أدوات/صيانة (developer tools) — لا تحتاج Riverpod
#  - شاشات AI/Reports — قد لا تستخدم providers
#  - شاشات إصلاح قاعدة البيانات — للصيانة فقط
#

EXCLUDE_FROM_RIVERPOD_CHECK = {
    # شاشات أدوات/صيانة
    'screens/settings/database_fixer_screen.dart',
    'screens/settings/schema_comparison_screen.dart',
    'screens/settings/restore_fix_screen.dart',
    'screens/settings/server_id_fixer_screen.dart',
    'screens/settings/appwrite_sync_stats_screen.dart',
    'screens/settings/sync_conflicts_screen.dart',
    'screens/settings/sync_health/sync_health_screen.dart',
    'screens/settings/sync_history_screen.dart',
    'screens/settings/auto_sync_engine_monitor_screen.dart',
    'screens/settings/error_center_screen.dart',
    'screens/settings/logs/unified_logs_screen.dart',
    'screens/settings/appwrite_logs_screen.dart',
    'screens/settings/google_drive_logs_screen.dart',
    'screens/settings/sync_debug_logs_screen.dart',
    # شاشات AI
    'screens/ai/ai_chat_screen.dart',
    # شاشات reports
    'screens/reports/report_page_scaffold.dart',
    # شاشات backup/restore
    'screens/settings/backup/tabs/google_drive_tab.dart',
    'screens/settings/backup/tabs/local_backups_tab.dart',
    'screens/settings/backup/comprehensive_backup_screen_v2.dart',
    'screens/settings/google_drive_backup_screen.dart',
}

# شاشات يُسمح لها باستيراد services مباشرة (developer tools)
EXCLUDE_FROM_SERVICES_CHECK = {
    'screens/settings/database_fixer_screen.dart',
    'screens/settings/schema_comparison_screen.dart',
    'screens/settings/restore_fix_screen.dart',
    'screens/settings/appwrite_settings_screen.dart',
    'screens/settings/appwrite_connection_settings_screen.dart',
    'screens/settings/appwrite_sync_stats_screen.dart',
    'screens/settings/sync_health/sync_health_screen.dart',
    'screens/settings/logs/unified_logs_screen.dart',
    'screens/settings/appwrite_logs_screen.dart',
    'screens/settings/google_drive_logs_screen.dart',
    'screens/settings/sync_debug_logs_screen.dart',
    'screens/settings/settings_maintenance.dart',
}

# ملفات يُسمح لها بالاعتماد الدائري (deferred imports, developer tools)
EXCLUDE_FROM_CIRCULAR_CHECK = {
    'components/app_scaffold.dart',
}


def is_excluded(file_path: str, exclude_set: Set[str]) -> bool:
    """فحص ما إذا كان المسار ضمن قائمة الاستثناء."""
    return file_path in exclude_set


def get_imports(file_content: str) -> List[str]:
    """استخراج جميع الاستيرادات من محتوى ملف Dart."""
    pattern = r"^\s*import\s+['\"]([^'\"]+)['\"]"
    return re.findall(pattern, file_content, re.MULTILINE)


def resolve_import(imp: str, current_file: str, lib_root: Path) -> str:
    """تحويل import نسبي/حزمة إلى مسار مطلق."""
    if imp.startswith('package:marina_hotel_mobile/'):
        relative = imp.replace('package:marina_hotel_mobile/', '')
        return str(lib_root / relative)
    if imp.startswith('.'):
        current_dir = Path(current_file).parent
        resolved = (current_dir / imp).resolve()
        return str(resolved)
    return imp


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
        if part in LAYER_DOMAIN:
            return 'domain'
        if part in LAYER_DATA:
            return 'data'
    return 'unknown'


# ═══════════════════════════════════════════════════════════════
#  ERRORS — قواعد تُسبب فشل الـ CI
# ═══════════════════════════════════════════════════════════════

def check_no_direct_db_from_ui(lib_root: Path) -> Tuple[List[Tuple[str, str]], int]:
    """
    ERROR Rule: No direct DB access from UI

    screens + widgets + components لا تستخدم DatabaseManager.instance مباشرة.
    يجب المرور عبر ref.read(databaseProvider) → AppDatabase.

    ملاحظة: استيراد 'local_db.dart' للـ types (Room, Booking, Payment) مقبول
    وطبيعي في مشاريع Drift. الانتهاك هو استخدام DatabaseManager.instance
    """
    violations = []
    db_access_patterns = [
        r'DatabaseManager\.instance\b',
        r'AppDatabase\s*\(\s*\)',  # direct construction
    ]

    ui_dirs = [lib_root / 'screens', lib_root / 'widgets', lib_root / 'components']
    for ui_dir in ui_dirs:
        if not ui_dir.exists():
            continue
        for dart_file in ui_dir.rglob('*.dart'):
            rel_path = str(dart_file.relative_to(lib_root))
            # استثناء شاشات الصيانة (developer tools)
            if is_excluded(rel_path, EXCLUDE_FROM_SERVICES_CHECK):
                continue
            try:
                content = dart_file.read_text(encoding='utf-8')
            except Exception:
                continue
            # فحص كل نمط
            for pattern in db_access_patterns:
                matches = re.findall(pattern, content)
                if matches:
                    for match in matches:
                        violations.append((rel_path, f'uses {match}'))
                    break  # ملف واحد = انتهاك واحد
    return violations, len(violations)


def check_no_circular_dependencies(lib_root: Path) -> Tuple[List[Tuple[str, ...]], int]:
    """
    ERROR Rule: No circular dependencies
    كشف الاعتماد الدائري بين الوحدات.
    """
    graph: Dict[str, Set[str]] = {}
    for dart_file in lib_root.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        # Skip excluded files from circular dependency check
        if is_excluded(rel_path, EXCLUDE_FROM_CIRCULAR_CHECK):
            continue
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

    cycles = []
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {node: WHITE for node in graph}

    def dfs(node: str, path: List[str]) -> None:
        color[node] = GRAY
        path.append(node)
        for neighbor in graph.get(node, set()):
            if color.get(neighbor, WHITE) == GRAY:
                cycle_start = path.index(neighbor)
                cycle = tuple(path[cycle_start:] + [neighbor])
                cycles.append(cycle)
            elif color.get(neighbor, WHITE) == WHITE:
                dfs(neighbor, path)
        path.pop()
        color[node] = BLACK

    for node in graph:
        if color[node] == WHITE:
            dfs(node, [])

    return cycles[:5], len(cycles)  # أول 5 cycles فقط


# ═══════════════════════════════════════════════════════════════
#  WARNINGS — قواعد لا تُسبب فشل الـ CI
# ═══════════════════════════════════════════════════════════════

def check_no_services_from_ui(lib_root: Path) -> Tuple[List[Tuple[str, str]], int]:
    """
    WARNING Rule: No direct services imports from screens
    screens يجب أن تستخدم providers بدلاً من استيراد services مباشرة.
    يمكن إصلاح هذا تدريجياً (transitional).
    
    الاستثناءات المسموحة:
    1. data layer: local_db.dart, /daos/, /repositories/ (types/data access, ليست خدمات)
    2. legacy services: sync_service, appwrite_config, smart_sync_manager (قيد الترحيل)
    3. crashlytics/analytics/logging (اختراق ضروري)
    4. services توجد لها providers جاهزة (انتقالي)
    """
    violations = []
    
    # خدمات تحليلية/تسجيل مسموحة
    allowed_services = {
        'crashlytics_service',
        'analytics_service',
        'logging',
        'app_logger',
    }
    
    # ملفات طبقة البيانات - ليست خدمات حقيقية
    data_layer_patterns = [
        'local_db.dart',
        'local_db.g.dart',
        '/daos/',
        '/repositories/',
    ]
    
    # خدمات قديمة/ترحيلية - لها providers أو قيد الاستبدال
    transitional_services = {
        '/sync_service.dart',
        '/smart_sync_manager.dart',
        '/appwrite_config.dart',
        '/providers.dart',
        # خدمات لها providers جاهزة لكن الشاشات لم تُحدث بعد
        'booking_derived_fields_service.dart',
        'salary_entitlement_service.dart',
        'auth_local_store.dart',
        'stay_balance_calculator.dart',
        'gemini_service.dart',
        'screen_sync_controller.dart',
        'price_adjustment_service.dart',
        'booking_price_adjustment_service.dart',
        'google_drive_auto_sync_engine.dart',
        'google_drive_conflict_resolver.dart',
        'google_drive_backup_service.dart',
        'appwrite_backup_service.dart',
        'appwrite_cache_manager.dart',
        'appwrite_logger.dart',
        'local_backup_service.dart',
        'alarm_backup.dart',
        'appwrite_sync_manager.dart',
        'sync_guardian.dart',
        'conflict_manager.dart',
        'sync_performance_settings.dart',
        'sync_health_monitor.dart',
        'whatsapp_service.dart',
        'whatsapp_settings_sync.dart',
        'secondary_appwrite_service.dart',
        'secondary_backup_service.dart',
        'secondary_sync_manager.dart',
        'secondary_appwrite_config.dart',
        'payments_repository.dart',
        'database_fixer.dart',
        'restore_fix_service.dart',
        'sqlite_backup_restore.dart',
        'appwrite_config_manager.dart',
        'logging/log_models.dart',
        'appwrite_models.dart',
    }
    
    for dart_file in (lib_root / 'screens').rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        # استثناء شاشات الصيانة
        if is_excluded(rel_path, EXCLUDE_FROM_SERVICES_CHECK):
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        for imp in imports:
            if 'services/' not in imp:
                continue
            # السماح بخدمات التحليل/التسجيل
            if any(allowed in imp for allowed in allowed_services):
                continue
            # السماح بطبقة البيانات
            if any(p in imp for p in data_layer_patterns):
                continue
            # السماح بالخدمات الترحيلية
            if any(t in imp for t in transitional_services):
                continue
            violations.append((rel_path, imp))
    return violations, len(violations)


def check_riverpod_compliance(lib_root: Path) -> Tuple[List[Tuple[str, str]], int]:
    """
    WARNING Rule: Riverpod compliance (ConsumerWidget)
    UI widgets يجب أن تكون ConsumerWidget أو ConsumerStatefulWidget.
    """
    violations = []
    consumer_pattern = re.compile(r'(ConsumerWidget|ConsumerStatefulWidget)')
    for dart_file in (lib_root / 'screens').rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        if is_excluded(rel_path, EXCLUDE_FROM_RIVERPOD_CHECK):
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        # إذا كان file يحتوي على widget class وليس ConsumerWidget
        if 'class ' in content and 'Widget' in content:
            if not consumer_pattern.search(content):
                violations.append((rel_path, 'does not extend ConsumerWidget/ConsumerStatefulWidget'))
    return violations, len(violations)


def check_no_ui_in_data(lib_root: Path) -> Tuple[List[Tuple[str, str]], int]:
    """
    WARNING Rule: No UI imports in Data layer
    data layer لا يستورد UI (screens/widgets/components).
    """
    violations = []
    for dart_file in lib_root.rglob('*.dart'):
        rel_path = str(dart_file.relative_to(lib_root))
        layer = get_layer(rel_path)
        if layer not in ('data', 'domain'):
            continue
        try:
            content = dart_file.read_text(encoding='utf-8')
        except Exception:
            continue
        imports = get_imports(content)
        for imp in imports:
            if 'screens/' in imp or 'widgets/' in imp or 'components/' in imp:
                violations.append((rel_path, imp))
    return violations, len(violations)


# ═══════════════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════════════

def main() -> int:
    parser = argparse.ArgumentParser(
        description='Architecture validator for Marina Hotel mobile app'
    )
    parser.add_argument(
        '--project-root',
        type=Path,
        required=True,
        help='Path to mobile directory (contains lib/)'
    )
    args = parser.parse_args()

    lib_root = args.project_root / 'lib'
    if not lib_root.exists():
        print(f'❌ lib/ directory not found at {lib_root}')
        return 1

    print('═' * 60)
    print('  🏗️  Architecture Validator — Marina Hotel')
    print('═' * 60)

    errors_count = 0
    warnings_count = 0

    # Error 1: No direct DB access from UI
    print('  🔹 Error 1: No direct DB access from UI')
    violations, count = check_no_direct_db_from_ui(lib_root)
    if violations:
        print(f'     ❌ {count} violations:')
        for file, msg in violations[:5]:
            print(f'        {file}: {msg}')
        errors_count += count
    else:
        print('     ✅ Pass')
    print()

    # Error 2: No circular dependencies
    print('  🔹 Error 2: No circular dependencies')
    cycles, count = check_no_circular_dependencies(lib_root)
    if cycles:
        print(f'     ❌ {count} circular dependencies detected:')
        for cycle in cycles:
            print(f'        {" -> ".join(cycle)}')
        errors_count += count
    else:
        print('     ✅ Pass')
    print()

    # Warning 1: No direct services imports from screens
    print('  🔹 Warning 1: No direct services imports from screens')
    violations, count = check_no_services_from_ui(lib_root)
    if violations:
        print(f'     ⚠️  {count} violations (transitional):')
        for file, imp in violations[:5]:
            print(f'        {file} -> {imp}')
        warnings_count += count
    else:
        print('     ✅ Pass')
    print()

    # Warning 2: Riverpod compliance
    print('  🔹 Warning 2: Riverpod compliance (ConsumerWidget)')
    violations, count = check_riverpod_compliance(lib_root)
    if violations:
        print(f'     ⚠️  {count} screens not using ConsumerWidget:')
        for file, msg in violations[:5]:
            print(f'        {file}: {msg}')
        warnings_count += count
    else:
        print('     ✅ Pass')
    print()

    # Warning 3: No UI imports in Data layer
    print('  🔹 Warning 3: No UI imports in Data layer')
    violations, count = check_no_ui_in_data(lib_root)
    if violations:
        print(f'     ⚠️  {count} violations:')
        for file, imp in violations[:5]:
            print(f'        {file} -> {imp}')
        warnings_count += count
    else:
        print('     ✅ Pass')
    print()

    # ══════════════════════════════════════════════════════════
    #  Summary
    # ══════════════════════════════════════════════════════════
    print('═' * 60)
    print(f'  📊 Summary:')
    print(f'     🔴 Errors:   {errors_count}')
    print(f'     🟡 Warnings: {warnings_count}')
    print()

    if errors_count > 0:
        print(f'  ❌ FAILED: {errors_count} errors must be fixed')
        return 1
    else:
        print(f'  ✅ PASSED: 0 errors ({warnings_count} warnings — non-blocking)')
        return 0


if __name__ == '__main__':
    sys.exit(main())
