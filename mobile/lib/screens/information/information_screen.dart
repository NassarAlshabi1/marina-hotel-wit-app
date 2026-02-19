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

class _InformationScreenState extends ConsumerState<InformationScreen>
    with SyncOnExitMixin {
  final TextEditingController _searchController = TextEditingController();
  final DateFormat _dateFormatter = DateFormat('yyyy/MM/dd');
  String _searchQuery = '';
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
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final filtered = _applySearch(entries);
    if (entries.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'لا توجد سجلات للمعلومية',
          subtitle: 'استخدم زر إضافة سجل لإدخال أول بيان للنزيل.',
          icon: Icons.badge_outlined,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'بحث برقم الغرفة أو اسم النزيل أو الهوية',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => _searchController.clear(),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          title: 'إجمالي السجلات',
                          value: '${entries.length}',
                          icon: Icons.folder_shared,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryTile(
                          title: 'بعد التصفية',
                          value: '${filtered.length}',
                          icon: Icons.filter_list,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const EmptyState(
                  title: 'لا توجد نتائج مطابقة',
                  subtitle: 'جرّب تعديل معايير البحث.',
                  icon: Icons.search_off,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _buildTable(filtered),
                ),
        ),
      ],
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

  List<GuestInfo> _applySearch(List<GuestInfo> entries) {
    if (_searchQuery.isEmpty) {
      return entries;
    }
    final q = _searchQuery.toLowerCase();
    return entries.where((info) {
      return info.roomNumber.toLowerCase().contains(q) ||
          info.guestName.toLowerCase().contains(q) ||
          info.nationality.toLowerCase().contains(q) ||
          info.idNumber.toLowerCase().contains(q) ||
          (info.governorate ?? '').toLowerCase().contains(q);
    }).toList();
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
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
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
                        value: selectedIdType,
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
                            onPressed: () =>
                                _pickIssueDate(issueDateController),
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
                        decoration: const InputDecoration(
                          labelText: 'المحافظة',
                        ),
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
          ),
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
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
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
      ),
    );

    if (shouldDelete != true) return;

    await ref.read(guestInfoRepoProvider).delete(info.id);
    markDataChanged();
    _showSnack('تم حذف السجل');
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

    setState(() => _exportingPdf = true);
    try {
      final fonts = await PdfUtils.loadArabicFonts();
      final logo = await PdfUtils.loadLogoImage();
      final prefs = await SharedPreferences.getInstance();
      final hotelName = prefs.getString('hotel_name') ?? 'فندق مارينا بلازا';
      final headers = [
        'اسم الفندق',
        'رقم الغرفة',
        'اسم النزيل',
        'الجنسية',
        'رقم الهوية',
        'نوع الهوية',
        'تاريخ الإصدار',
        'مكان الإصدار',
        'المحافظة',
      ];
      final data = entries
          .map(
            (info) => [
              hotelName,
              info.roomNumber,
              info.guestName,
              info.nationality,
              info.idNumber,
              info.idType ?? '-',
              info.issueDate ?? '-',
              info.issuePlace ?? '-',
              info.governorate ?? '-',
            ],
          )
          .toList();

      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (logo != null)
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Image(logo, width: 64),
                ),
              pw.Text(
                hotelName,
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 18,
                  color: pdf.PdfColors.blue800,
                ),
              ),
              pw.Text(
                'سجل المعلومية',
                style: pw.TextStyle(
                  font: fonts.base,
                  fontSize: 14,
                  color: pdf.PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (context) => [
            pw.Table.fromTextArray(
              headers: headers,
              data: data,
              headerDecoration: const pw.BoxDecoration(
                color: pdf.PdfColors.blue800,
              ),
              headerStyle: pw.TextStyle(
                font: fonts.bold,
                color: pdf.PdfColors.white,
                fontSize: 11,
              ),
              cellStyle: pw.TextStyle(font: fonts.base, fontSize: 10),
              cellAlignment: pw.Alignment.centerLeft,
              border:
                  pw.TableBorder.all(color: pdf.PdfColors.grey400, width: 0.5),
            ),
          ],
        ),
      );

      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'guest-info-$timestamp.pdf';
      await Printing.sharePdf(bytes: await doc.save(), filename: filename);
    } catch (error) {
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
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge),
              Text(title, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}
