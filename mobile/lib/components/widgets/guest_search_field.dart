import 'package:flutter/material.dart';

/// حقل بحث «سجل المعلومية» — مكوّن مستقل قابل للاختبار بلا قاعدة بيانات.
///
/// ✅ (2026-10-06) طلب المالك: «اضافة في الهيد في شاشة information guest —
/// عند الضغط عليه باستطاعتي البحث في سجل المعلومية بالاسم».
///
/// يُستخدم كـ `AppScaffold.header` ويُفتح بالضغط على أيقونة البحث في الـ
/// AppBar (إدارة الظهور في الشاشة نفسها)، فلا يزحم الرأس قبل الضغط.
class GuestSearchField extends StatelessWidget {
  const GuestSearchField({
    required this.controller,
    required this.onChanged,
    super.key,
    this.focusNode,
    this.hintText = 'ابحث في سجل المعلومية بالاسم أو الغرفة أو الهوية…',
    this.onCleared,
    this.showClearButton = true,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String hintText;

  /// يُستدعى بعد تفريغ الحقل (اختياري — لإعادة بناء النتائج فوراً).
  final VoidCallback? onCleared;
  final bool showClearButton;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: !showClearButton || controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                  onCleared?.call();
                },
              ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
}
