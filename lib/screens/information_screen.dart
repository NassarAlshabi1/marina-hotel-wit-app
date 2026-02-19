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
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/pdf_utils.dart';

class InformationScreen extends ConsumerStatefulWidget {
  const InformationScreen({super.key});

  @override
  ConsumerState<InformationScreen> createState() => _InformationScreenState();
}

class _InformationScreenState extends ConsumerState<InformationScreen> with SyncOnExitMixin {
  bool _exportingPdf = false;

  static final List<String> _idTypes = [
    'بطاقة شخصية',
    'جواز سفر',
    'إقامة',
    'رخصة قيادة',
    'بطاقة عائلية',
  ];

  @override
  String get screenId => 'information_screen';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guestInfosAsync = ref.watch(guestInfoListProvider);
    final currentEntries = guestInfosAsync.maybeWhen(
      data: (data) => data,
      orElse: () => const <GuestInfo>[],
    );

    return wrapWithSyncOnExit(
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
          data: (entries) => _buildContent(entries),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) =>
              Center(child: Text('حدث خطأ أثناء تحميل البيانات: $error')), 
        ),
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

    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildTable(entries),
    );
  }

  Widget _buildTable(List<GuestInfo> entries) {
    final headers = [
      'الغرفة',
      'اسم النزيل',
      'الجنسية',
      'رقم الهوية',
      'نوع الهوية',
      'تاريخ الإصدار',
      'مكان الإصدار',
      'المحافظة',
      'الإجراءات',
    ];

    return Card(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.primary,
          ),
          headingTextStyle: const TextStyle(color: Colors.white),
          columns: headers
              .map(
                (h) => DataColumn(
                  label: Text(
                    h,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              )
              .toList(),
          rows: entries
              .map(
                (info) => DataRow(
                  cells: [
                    DataCell(Text(info.roomNumber)),
                    DataCell(Text(info.guestName)),
                    DataCell(Text(info.nationality)),
                    DataCell(Text(info.idNumber)),
                    DataCell(Text(info.idType ?? '-')), 
                    DataCell(Text(info.issueDate ?? '-')),
                    DataCell(Text(info.issuePlace ?? '-')),
                    DataCell(Text(info.governorate ?? '-')),
                    DataCell(
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'تعديل',
                            icon: const Icon(Icons.edit, size: 20),
                            onPressed: () =>
                                _openEditor(context, existing: info),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () => _confirmDelete(info),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .toList(),
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
      text: existing?.nationality ?? '',
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
                      decoration:
                          const InputDecoration(labelText: 'رقم الغرفة'),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: guestNameController,
                      decoration:
                          const InputDecoration(labelText: 'اسم النزيل'),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: nationalityController,
                      decoration: const InputDecoration(labelText: 'الجنسية'),
                      validator: _requiredValidator,
                    ),
                    TextFormField(
                      controller: idNumberController,
                      decoration:
                          const InputDecoration(labelText: 'رقم الهوية'),
                      validator: _requiredValidator,
                    ),
                    DropdownButtonFormField<String>(
                      value: selectedIdType,
                      decoration:
                          const InputDecoration(labelText: 'نوع الهوية'),
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
                      decoration:
                          const InputDecoration(labelText: 'مكان الإصدار'),
                    ),
                    TextFormField(
                      controller: governorateController,
                      decoration: const InputDecoration(labelText: 'المحافظة'),
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

    if (confirmed != true) return;

    final repo = ref.read(guestInfoRepoProvider);
    if (existing == null) {
      await repo.create(
        roomNumber: roomController.text,
        guestName: guestNameController.text,
        nationality: nationalityController.text,
        idNumber: idNumberController.text,
        idType: selectedIdType,
        issueDate:
            issueDateController.text.isEmpty ? null : issueDateController.text,
        issuePlace: issuePlaceController.text,
        governorate: governorateController.text,
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
      );
      _showSnack('تم تحديث السجل بنجاح');
    }

    markDataChanged();
  }

  Future<void> _confirmDelete(GuestInfo info) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('حذف السجل'),
        content: Text(
          'سيتم حذف سجل النزيل "${info.guestName}"، هل أنت متأكد؟',
        ),
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

    if (shouldDelete != true) return;

    await ref.read(guestInfoRepoProvider).delete(info.id);
    markDataChanged();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم حذف السجل'),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () async {
            await ref.read(guestInfoRepoProvider).create(
              roomNumber: info.roomNumber,
              guestName: info.guestName,
              nationality: info.nationality,
              idNumber: info.idNumber,
              idType: info.idType,
              issueDate: info.issueDate,
              issuePlace: info.issuePlace,
              governorate: info.governorate,
            );
            markDataChanged();
            _showSnack('تم استعادة السجل');
          },
        ),
        duration: Duration(seconds: 5),
      ),
    );
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
  final pdfDoc = pw.Document();

  final fontData = await rootBundle.load('assets/fonts/Cairo-Regular.ttf');
  final boldFontData = await rootBundle.load('assets/fonts/Cairo-Bold.ttf');

  final fonts = (
    base: pw.Font.ttf(fontData),
    bold: pw.Font.ttf(boldFontData),
  );

  final headers = [
    'رقم الغرفة',
    'اسم النزيل',
    'الجنسية',
    'نوع الهوية',
    'رقم الهوية',
    'تاريخ الإصدار',
    'مكان الإصدار',
    'المحافظة',
  ];

  final data = entries.map((e) => [
        e.roomNumber ?? '-',
        e.guestName ?? '-',
        e.nationality ?? '-',
        e.idType ?? '-',
        e.idNumber ?? '-',
        e.issueDate ?? '-',
        e.issuePlace ?? '-',
        e.governorate ?? '-',
      ]).toList();

  pdfDoc.addPage(
    pw.MultiPage(
      pageFormat: pdf.PdfPageFormat.a4.landscape,
      build: (context) => [
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Align(
                alignment: pw.Alignment.centerLeft,
                child: pw.Text(
                  DateFormat('yyyy-MM-dd').format(DateTime.now()),
                  style: pw.TextStyle(font: fonts.base, fontSize: 14),
                ),
              ),

              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('فندق مارينا',
                        style:
                            pw.TextStyle(font: fonts.bold, fontSize: 16)),
                    pw.Text(
                      'القاهرة - شارع أحمد قاسم | هاتف: 02324457',
                      style: pw.TextStyle(font: fonts.base, fontSize: 12),
                    ),
                  ],
                ),
              ),

              pw.Divider(),
              pw.Text('سجل بيانات النزلاء',
                  style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
              pw.SizedBox(height: 10),

              pw.Table.fromTextArray(
                headers: headers,
                data: data,
                cellAlignment: pw.Alignment.centerRight,
                border: pw.TableBorder.all(
                    color: pdf.PdfColors.grey400, width: 0.5),
                headerStyle: pw.TextStyle(
                    font: fonts.bold,
                    color: pdf.PdfColors.white,
                    fontSize: 10),
                headerDecoration:
                    const pw.BoxDecoration(color: pdf.PdfColors.blue800),
                cellStyle:
                    pw.TextStyle(font: fonts.base, fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  await Printing.layoutPdf(onLayout: (f) async => pdfDoc.save());
}
