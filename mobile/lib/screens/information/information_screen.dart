// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart' as appwrite;
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/pdf_utils.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class InformationScreen extends ConsumerStatefulWidget {
  const InformationScreen({super.key});

  @override
  ConsumerState<InformationScreen> createState() => _InformationScreenState();
}

class _InformationScreenState extends ConsumerState<InformationScreen>
    with SyncOnExitMixin {
  bool _exportingPdf = false;
  final _verticalScrollController = ScrollController();

  @override
  void dispose() {
    _verticalScrollController.dispose();
    super.dispose();
  }

  static final List<String> _idTypes = [
    'بطاقة شخصية',
    'جواز سفر',
    'إقامة',
    'رخصة قيادة',
    'بطاقة عائلية',
    'شهادة ميلاد',
    'بطاقة رقم جلوس',
    'استبيان',
  ];

  @override
  String get screenId => 'information_screen';

  @override
  Widget build(BuildContext context) {
    final guestInfosAsync = ref.watch(guestInfoListProvider);
    final currentEntries = guestInfosAsync.maybeWhen(
      data: (data) => data,
      orElse: () => const <GuestInfo>[],
    );

    return PopScope(
      canPop: !hasUnsyncedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _showDiscardDialog(context);
      },
      child: AppScaffold(
        title: 'سجل المعلومية',
        actions: [
          IconButton(
            tooltip: 'تصدير إلى PDF',
            onPressed: _exportingPdf || currentEntries.isEmpty
                ? null
                : () => _handleExport(currentEntries),
            icon: _exportingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf),
          ),
        ],
        fab: FloatingActionButton.extended(
          onPressed: () => _openEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('إضافة سجل'),
        ),
        body: guestInfosAsync.when(
          data: _buildContent,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('حدث خطأ أثناء تحميل البيانات: $error')),
        ),
      ),
    );
  }

  void _showDiscardDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: const Text('هل تريد المغادرة بدون حفظ التغييرات؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: const Text('مغادرة'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(List<GuestInfo> entries) {
    if (entries.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'لا توجد سجلات للمعلومية',
          subtitle: 'استخدم زر إضافة سجل لإدخال أول بيان للنزيل.',
          icon: Icons.badge_outlined,
        ),
      );
    }

    final scrollCtrl = _verticalScrollController;

    // ترتيب حسب رقم الغرفة (أرقام أولاً، ثم أبجدي)
    final sorted = List<GuestInfo>.from(entries);
    sorted.sort((a, b) {
      final aNum = int.tryParse(a.roomNumber);
      final bNum = int.tryParse(b.roomNumber);
      if (aNum != null && bNum != null) {
        return aNum.compareTo(bNum);
      }
      if (aNum != null) {
        return -1;
      }
      if (bNum != null) {
        return 1;
      }
      return a.roomNumber.compareTo(b.roomNumber);
    });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Scrollbar(
        controller: scrollCtrl,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: scrollCtrl,
          child: _buildTable(sorted),
        ),
      ),
    );
  }

  Widget _buildTable(List<GuestInfo> entries) {
    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.primary,
          ),
          headingTextStyle: const TextStyle(color: Colors.white),
          columns: const [
            DataColumn(
              label: Text('#', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            DataColumn(label: SizedBox.shrink()),
            DataColumn(
              label: Text(
                'الغرفة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'اسم النزيل',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'الجنسية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'رقم الهوية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'نوع الهوية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'تاريخ الإصدار',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'مكان الإصدار',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'المحافظة',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                'الملاحظات',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
          rows: List.generate(entries.length, (index) {
            final info = entries[index];
            return DataRow(
              cells: [
                DataCell(Text('${index + 1}')),
                DataCell(
                  PopupMenuButton<String>(
                    tooltip: 'إجراءات',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openEditor(context, existing: info);
                      } else if (value == 'delete') {
                        _confirmDelete(info);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('تعديل'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                            SizedBox(width: 8),
                            Text('حذف', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Text(
                    info.roomNumber,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                DataCell(Text(info.guestName)),
                DataCell(Text(info.nationality)),
                DataCell(Text(info.idNumber)),
                DataCell(Text(info.idType)),
                DataCell(Text(info.issueDate ?? '-')),
                DataCell(Text(info.issuePlace ?? '-')),
                DataCell(Text(info.governorate ?? '-')),
                DataCell(Text(info.notes ?? '-')),
              ],
            );
          }),
        ),
      ),
    );
  }

  Future<void> _openEditor(BuildContext context, {GuestInfo? existing}) async {
    final formKey = GlobalKey<FormState>();
    final roomController = TextEditingController(
      text: existing?.roomNumber ?? '',
    );
    final guestNameController = TextEditingController(
      text: existing?.guestName ?? '',
    );
    final nationalityController = TextEditingController(
      text: existing?.nationality.isNotEmpty ?? false
          ? existing!.nationality
          : 'يمني',
    );
    final idNumberController = TextEditingController(
      text: existing?.idNumber ?? '',
    );
    final issueDateController = TextEditingController(
      text: existing?.issueDate ?? '',
    );
    final issuePlaceController = TextEditingController(
      text: existing?.issuePlace ?? '',
    );
    final governorateController = TextEditingController(
      text: existing?.governorate ?? '',
    );
    final notesController = TextEditingController(text: existing?.notes ?? '');

    String selectedIdType = existing?.idType ?? _idTypes.first;
    if (!_idTypes.contains(selectedIdType)) {
      _idTypes.insert(0, selectedIdType);
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(existing == null ? 'إضافة معلومية' : 'تعديل معلومية'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الغرفة',
                      ),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: guestNameController,
                      decoration: const InputDecoration(
                        labelText: 'اسم النزيل',
                      ),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: nationalityController,
                      decoration: const InputDecoration(labelText: 'الجنسية'),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: idNumberController,
                      decoration: const InputDecoration(
                        labelText: 'رقم الهوية',
                      ),
                      validator: _requiredValidator,
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _idTypes.contains(selectedIdType)
                          ? selectedIdType
                          : null,
                      decoration: const InputDecoration(
                        labelText: 'نوع الهوية',
                      ),
                      items: _idTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(type),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) {
                          selectedIdType = value;
                        }
                      },
                    ),
                    TextFormField(
                      controller: issueDateController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'تاريخ الإصدار',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.date_range),
                          onPressed: () => _pickIssueDate(issueDateController),
                        ),
                      ),
                    ),
                    TextFormField(
                      controller: issuePlaceController,
                      decoration: const InputDecoration(
                        labelText: 'مكان الإصدار',
                      ),
                    ),
                    TextFormField(
                      controller: governorateController,
                      decoration: const InputDecoration(labelText: 'المحافظة'),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'الملاحظات',
                        alignLabelWithHint: true,
                      ),
                      maxLines: 3,
                      minLines: 1,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      },
    );
    roomController.dispose();
    guestNameController.dispose();
    nationalityController.dispose();
    idNumberController.dispose();
    issueDateController.dispose();
    issuePlaceController.dispose();
    governorateController.dispose();
    notesController.dispose();

    if (confirmed != true) {
      return;
    }

    final repo = ref.read(guestInfoRepoProvider);
    try {
      if (existing == null) {
        await repo.create(
          roomNumber: roomController.text,
          guestName: guestNameController.text,
          nationality: nationalityController.text,
          idNumber: idNumberController.text,
          idType: selectedIdType,
          issueDate: issueDateController.text.isEmpty
              ? null
              : issueDateController.text,
          issuePlace: issuePlaceController.text,
          governorate: governorateController.text,
          notes: notesController.text,
        );
        _showSnack('تم حفظ السجل بنجاح');
      } else {
        await repo.update(
          existing.id,
          roomNumber: roomController.text,
          guestName: guestNameController.text,
          nationality: nationalityController.text,
          idNumber: idNumberController.text,
          idType: selectedIdType,
          issueDate: issueDateController.text,
          issuePlace: issuePlaceController.text,
          governorate: governorateController.text,
          notes: notesController.text,
        );
        _showSnack('تم تحديث السجل بنجاح');
      }

      markDataChanged();
      unawaited(_pushToAppwrite());
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ السجل: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _confirmDelete(GuestInfo info) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السجل'),
        content: Text('سيتم حذف سجل النزيل "${info.guestName}"، هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (shouldDelete != true) {
      return;
    }

    try {
      await ref.read(guestInfoRepoProvider).delete(info.id);
      markDataChanged();
      _showSnack('تم حذف السجل');
      unawaited(_pushToAppwrite());
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text('فشل حذف السجل: $e'),
          backgroundColor: Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _pickIssueDate(TextEditingController controller) async {
    final initial = controller.text.isEmpty
        ? DateTime.now()
        : DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1990),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  Future<void> _handleExport(List<GuestInfo> entries) async {
    if (entries.isEmpty) {
      _showSnack('لا توجد بيانات للتصدير');
      return;
    }

    // ✅ Guard ضد double-press: لو ضغط المستخدم الزر مرتين سريعاً قبل أن يُعطّله
    // الـ UI (يحدث قبل أول await)، نتجنّب تشغيل عمليتي تصدير متزامنتين.
    if (_exportingPdf) return;

    setState(() => _exportingPdf = true);
    try {
      // ✅ تحميل الخطوط العربية أولاً — أي فشل هنا يُغلق العملية مبكراً برسالة واضحة.
      final fonts = await PdfUtils.loadArabicFonts();
      final prefs = await SharedPreferences.getInstance();
      final hotelName = prefs.getString('hotel_name') ?? 'فندق مارينا بلازا';
      final headers = [
        'الملاحظات',
        'المحافظة',
        'مكان الإصدار',
        'تاريخ الإصدار',
        'رقم الهوية',
        'نوع الهوية',
        'الجنسية',
        'اسم النزيل',
        'رقم الغرفة',
        '#',
      ];
      // ✅ Defensive null handling: الحقول non-nullable في schema، لكن قد تحتوي NULL
      // في قاعدة بيانات قديمة (قبل تطبيق NOT NULL) — عندئذ قراءتها كـ String تُسبب
      // TypeError صامت. نُحوّل كل حقل لـ String? ثم نستخدم ?? '-'.
      String safe(dynamic v) {
        if (v == null) return '-';
        final s = v.toString().trim();
        return s.isEmpty ? '-' : s;
      }

      final data = List.generate(entries.length, (i) {
        final info = entries[i];
        return [
          safe(info.notes),
          safe(info.governorate),
          safe(info.issuePlace),
          safe(info.issueDate),
          safe(info.idNumber),
          safe(info.idType),
          safe(info.nationality),
          safe(info.guestName),
          safe(info.roomNumber),
          '${i + 1}',
        ];
      });
      final printDate = DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now());

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          pageFormat: pdf.PdfPageFormat.a4.landscape,
          textDirection: pw.TextDirection.rtl,
          margin: const pw.EdgeInsets.only(
            top: 10,
            left: 20,
            right: 20,
            bottom: 20,
          ),
          theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
          header: (context) {
            return pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              children: [
                pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // الجهة اليمنى - اسم الفندق والعنوان
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            hotelName,
                            style: pw.TextStyle(
                              font: fonts.bold,
                              fontSize: 18,
                              color: pdf.PdfColors.blue900,
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'القاهرة - شارع أحمد قاسم',
                            style: pw.TextStyle(
                              font: fonts.base,
                              fontSize: 12,
                              color: pdf.PdfColors.grey800,
                            ),
                            textAlign: pw.TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                    // المنتصف - عنوان التقرير
                    pw.Expanded(
                      child: pw.Center(
                        child: pw.Text(
                          'سجل المعلومية',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 16,
                            color: pdf.PdfColors.grey800,
                          ),
                        ),
                      ),
                    ),
                    // الجهة اليسرى - تاريخ التقرير
                    pw.Expanded(
                      child: pw.Align(
                        alignment: pw.Alignment.centerLeft,
                        child: pw.Text(
                          'تاريخ التقرير: $printDate',
                          style: pw.TextStyle(
                            font: fonts.bold,
                            fontSize: 12,
                            color: pdf.PdfColors.grey800,
                          ),
                          textAlign: pw.TextAlign.left,
                        ),
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 10),
                pw.Divider(color: pdf.PdfColors.grey400),
                pw.SizedBox(height: 10),
              ],
            );
          },
          footer: (context) => pw.Column(
            children: [
              pw.Divider(color: pdf.PdfColors.grey400),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'تاريخ الطباعة: $printDate',
                    style: pw.TextStyle(font: fonts.base, fontSize: 10),
                  ),
                  pw.Text(
                    'صفحة ${context.pageNumber} من ${context.pagesCount}',
                    style: pw.TextStyle(font: fonts.base, fontSize: 10),
                  ),
                ],
              ),
            ],
          ),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: data,
              headerDecoration: const pw.BoxDecoration(
                color: pdf.PdfColors.blue800,
              ),
              headerStyle: pw.TextStyle(
                font: fonts.bold,
                color: pdf.PdfColors.white,
                fontSize: 10,
              ),
              cellStyle: pw.TextStyle(font: fonts.base, fontSize: 9),
              cellAlignment: pw.Alignment.center,
              border: pw.TableBorder.all(
                color: pdf.PdfColors.grey400,
                width: 0.5,
              ),
              headerAlignments: {
                0: pw.Alignment.centerRight,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
                7: pw.Alignment.centerRight,
                8: pw.Alignment.centerRight,
                9: pw.Alignment.center,
              },
            ),
          ],
        ),
      );

      // ✅ فصل doc.save() عن sharePdf — سهولة في التشخيص وضمان اكتمال التوليد قبل المشاركة.
      final Uint8List pdfBytes = await doc.save();
      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'guest-info-$timestamp.pdf';
      await Printing.sharePdf(bytes: pdfBytes, filename: filename);
    } catch (error, stackTrace) {
      // ✅ تشخيص مفصّل: نُسجّل الـ stackTrace في console + نُظهر رسالة واضحة للمستخدم.
      dlog(
        () =>
            '❌ فشل تصدير PDF لسجل المعلومية:\n  error: $error\n  stack: $stackTrace',
      );
      _showSnack('فشل تصدير الملف: $error');
    } finally {
      if (mounted) {
        setState(() => _exportingPdf = false);
      }
    }
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'هذا الحقل مطلوب';
    }
    return null;
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// مزامنة فورية إلى Appwrite بعد كل عملية CRUD
  Future<void> _pushToAppwrite() async {
    try {
      final syncManager = ref.read(appwrite.appwriteSyncManagerProvider);
      await syncManager.sync(pull: false);
    } catch (e) {
      dlog(() => '⚠️ فشلت المزامنة الفورية: $e');
    }
  }
}
