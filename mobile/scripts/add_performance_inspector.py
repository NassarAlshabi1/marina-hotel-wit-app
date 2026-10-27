#!/usr/bin/env python3
"""
Marina Hotel — PerformanceInspector Auto-Injector (v2 — safer)
==============================================================
يضيف PerformanceInspector widget لكل الشاشات في lib/screens/ التي
لا تستخدم AppScaffold أو AdminLayout (اللتان تمت تغطيتهما مسبقاً).

الاستراتيجية v2 (أكثر أماناً):
- يبحث عن `return Scaffold(` أو `return Directionality(`
- يضيف PerformanceInspector wrapper قبلها
- يضيف `)` إضافية في نهاية الـ statement (قبل الـ `;`)
- يتعامل مع المسافات البادئة بشكل صحيح
"""

import re
import sys
from pathlib import Path


def find_screen_files(lib_dir: Path) -> list[Path]:
    """يُعيد كل ملفات Dart في lib/screens/"""
    return sorted((lib_dir / 'screens').rglob('*.dart'))


def needs_inspector(file_path: Path) -> bool:
    """يتحقق إن كان الملف يحتاج لإضافة PerformanceInspector"""
    content = file_path.read_text(encoding='utf-8')
    if 'PerformanceInspector' in content:
        return False
    if 'AppScaffold(' in content or 'AdminLayout(' in content:
        return False
    if 'return Scaffold(' not in content and 'return Directionality(' not in content:
        return False
    return True


def get_class_name(content: str) -> str | None:
    """يستخرج اسم الـ class الرئيسي من الملف"""
    match = re.search(r'^class\s+(\w+)\s+extends\s+', content, re.MULTILINE)
    if match:
        return match.group(1)
    return None


def get_import_path(file_path: Path, lib_dir: Path) -> str:
    """يحسب المسار النسبي من الملف إلى utils/performance_monitor.dart"""
    rel = file_path.relative_to(lib_dir)
    depth = len(rel.parts) - 1
    if depth == 0:
        return "import 'performance_monitor.dart';"
    prefix = '../' * depth
    return f"import '{prefix}utils/performance_monitor.dart';"


def add_import(content: str, import_line: str) -> str:
    """يضيف import بعد آخر import موجود"""
    imports = list(re.finditer(r"^import\s+['\"][^'\"]+['\"];.*$", content, re.MULTILINE))
    if not imports:
        return import_line + '\n\n' + content
    last_import = imports[-1]
    pos = last_import.end()
    return content[:pos] + '\n' + import_line + content[pos:]


def find_matching_close(content: str, open_pos: int) -> int | None:
    """يجد موضع `)` المطابقة لـ `(` في open_pos"""
    depth = 0
    i = open_pos
    while i < len(content):
        if content[i] == '(':
            depth += 1
        elif content[i] == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return None


def wrap_scaffold_with_inspector(content: str, class_name: str) -> str | None:
    """
    يبحث عن `return Scaffold(` أو `return Directionality(`
    ويُغلِّفها بـ PerformanceInspector بطريقة آمنة.
    """
    # نبحث عن أول `return Scaffold(` أو `return Directionality(` في الـ build
    # استخدام ([ \t]+) بدلاً من (\s+) لتجنب التقاط الأسطر الفارغة
    patterns = [
        r'(\n)([ \t]+)return\s+Scaffold\(',
        r'(\n)([ \t]+)return\s+Directionality\(',
    ]

    for pattern in patterns:
        match = re.search(pattern, content)
        if not match:
            continue

        newline = match.group(1)  # \n فقط
        indent = match.group(2)   # المسافة البادئة (مسافات أو tabs فقط)
        return_kw_start = match.start() + len(newline) + len(indent)  # موضع `return`
        scaffold_open_pos = match.end() - 1  # موضع `(`

        # إيجاد `)` المطابقة
        close_pos = find_matching_close(content, scaffold_open_pos)
        if close_pos is None:
            continue

        # تحقق إن كان هناك `;` مباشرة بعد `)` (مع تجاهل whitespace)
        after_close = content[close_pos + 1:close_pos + 10]
        if not re.match(r'\s*;', after_close):
            continue

        # استخراج الـ Scaffold statement كاملاً (من `return` إلى `)`)
        scaffold_text = content[return_kw_start:close_pos + 1]

        # بناء الـ wrapper الجديد — بشكل نظيف بدون مسافات فارغة
        # الأصلي: `    return Scaffold(...)`
        # الجديد: 
        #   `    return PerformanceInspector(`
        #   `      name: 'ClassName',`
        #   `      child: Scaffold(...)`
        #   `    )`
        scaffold_inner = scaffold_text[len('return '):]  # يُزيل `return `
        new_text = (
            f'return PerformanceInspector(\n'
            f'{indent}  name: \'{class_name}\',\n'
            f'{indent}  child: {scaffold_inner}\n'
            f'{indent})'
        )

        # استبدال: من return_kw_start إلى close_pos + 1 (شامل `)` الأصلي)
        new_content = content[:return_kw_start] + new_text + content[close_pos + 1:]

        # تنظيف: إزالة الأسطر الفارغة الزائدة بين `)` و `;`
        new_content = re.sub(r'\)\n[ \t]*\n[ \t]*\n[ \t]*;', ');\n', new_content)
        new_content = re.sub(r'\)\n[ \t]*\n[ \t]*;', ');\n', new_content)

        return new_content

    return None


def process_file(file_path: Path, lib_dir: Path) -> tuple[bool, str]:
    """يعالج ملف واحد. يُعيد (success, message)"""
    try:
        content = file_path.read_text(encoding='utf-8')
    except Exception as e:
        return False, f'قراءة فشلت: {e}'

    if not needs_inspector(file_path):
        return False, 'متخطَّى (يستخدم AppScaffold أو PerformanceInspector بالفعل)'

    class_name = get_class_name(content)
    if not class_name:
        return False, 'لم يُعثر على class رئيسي'

    # إضافة import
    import_line = get_import_path(file_path, lib_dir)
    if import_line not in content:
        content = add_import(content, import_line)

    # wrap الـ Scaffold/Directionality
    new_content = wrap_scaffold_with_inspector(content, class_name)
    if new_content is None:
        return False, 'لم يُعثر على return Scaffold/Directionality قابل للالتفاف'

    # حفظ
    file_path.write_text(new_content, encoding='utf-8')
    return True, f'تم إضافة PerformanceInspector لـ {class_name}'


def main():
    mobile_dir = Path(__file__).parent.parent
    lib_dir = mobile_dir / 'lib'

    if not lib_dir.exists():
        print(f'ERROR: {lib_dir} غير موجود')
        sys.exit(1)

    print('=' * 70)
    print('Marina Hotel — PerformanceInspector Auto-Injector v2')
    print('=' * 70)
    print()

    screen_files = find_screen_files(lib_dir)
    print(f'إجمالي الملفات في lib/screens/: {len(screen_files)}')
    print()

    modified = 0
    skipped = 0
    failed = 0

    for file_path in screen_files:
        rel_path = file_path.relative_to(mobile_dir)
        success, msg = process_file(file_path, lib_dir)
        status_icon = '✅' if success else ('⏭️ ' if 'متخطَّى' in msg else '❌')
        print(f'{status_icon} {rel_path}: {msg}')
        if success:
            modified += 1
        elif 'متخطَّى' in msg:
            skipped += 1
        else:
            failed += 1

    print()
    print('=' * 70)
    print(f'النتيجة: {modified} مُعدَّل، {skipped} متخطَّى، {failed} فشل')
    print('=' * 70)

    if failed > 0:
        sys.exit(1)


if __name__ == '__main__':
    main()
