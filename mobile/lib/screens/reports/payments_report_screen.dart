import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/local_db.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';

class PaymentsReportScreen extends ConsumerStatefulWidget {
  const PaymentsReportScreen({super.key});

  @override
  ConsumerState<PaymentsReportScreen> createState() =>
      _PaymentsReportScreenState();
}

class _PaymentsReportScreenState extends ConsumerState<PaymentsReportScreen> {
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd HH:mm');
  final NumberFormat _currencyFmt = NumberFormat('#,##0', 'en_US');
  final _filterController = DateFilterController();

  // ignore: unused_element
  String _formatNumber(num value) => _currencyFmt.format(value);

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedRoom;
  bool _loading = false;
  bool _roomsLoaded = false;

  final List<_PaymentReportRow> _rows = [];
  final List<String> _availableRooms = [];

  double _totalPaid = 0;
  double _totalOtherPaid = 0;

  String _formatBookingCode(int bookingId) =>
      bookingId.toString().padLeft(6, '0');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_roomsLoaded) {
      _roomsLoaded = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    // الافتراضي: من بداية اليوم إلى نهاية اليوم التالي
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day + 1, 23, 59, 59);
    await _loadRooms();
    // تحديث القيم المحسوبة (totalDueCached, totalPaidCached, remainingBalanceCached)
    // لضمان دقة المجاميع في التقرير
    try {
      final db = ref.read(coreProviders.dbProvider);
      final derivedService = BookingDerivedFieldsService(db);
      await derivedService.refreshAllActiveBookings();
    } catch (_) {}
    await _fetchReport();
  }

  Future<void> _loadRooms() async {
    final db = ref.read(coreProviders.dbProvider);
    final rooms = await db.select(db.rooms).get();
    setState(() {
      _availableRooms
        ..clear()
        ..addAll(rooms.map((e) => e.roomNumber).toList()..sort());
      if (_availableRooms.isNotEmpty &&
          !_availableRooms.contains(_selectedRoom)) {
        _selectedRoom = null;
      }
    });
  }

  Future<void> _fetchReport() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(coreProviders.dbProvider);
      final result = await _loadPaymentsReport(db);
      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalPaid = result.totalPaid;
        _totalOtherPaid = result.totalOtherPaid;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<_PaymentsReportResult> _loadPaymentsReport(AppDatabase db) async {
    final outboxDao = OutboxDao(db);
    final paymentsDao = PaymentsDao(db, outboxDao);
    final fromStr = _fromDate != null
        ? '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_fromDate!)}'
        : null;
    final toStr = _toDate != null
        ? '${DateFormat('yyyy-MM-dd HH:mm:ss').format(_toDate!)}'
        : null;
    final payments = await paymentsDao.listForReport(
      from: fromStr,
      to: toStr,
      roomNumber: _selectedRoom,
    );

    final bookingIds = payments
        .map((p) => p.bookingLocalId)
        .whereType<int>()
        .toSet();
    final bookings = bookingIds.isEmpty
        ? <Booking>[]
        : await (db.select(
            db.bookings,
          )..where((tbl) => tbl.id.isIn(bookingIds))).get();
    final bookingMap = {for (final b in bookings) b.id: b};

    final roomNumbers = <String>{};
    for (final payment in payments) {
      final room = payment.roomNumber;
      if (room != null) roomNumbers.add(room);
      final bookingRoom = bookingMap[payment.bookingLocalId]?.roomNumber;
      if (bookingRoom != null) roomNumbers.add(bookingRoom);
    }
    // rooms لم تعد مطلوبة للحساب لأننا نستخدم القيم المحسوبة من الحجز مباشرة

    final rows = <_PaymentReportRow>[];
    double totalRoomPaid = 0;
    double totalOtherPaid = 0;
    final relevantBookingIds = <int>{};

    for (final payment in payments) {
      final booking = bookingMap[payment.bookingLocalId];
      final roomNumber =
          booking?.roomNumber ?? payment.roomNumber ?? 'غير محدد';
      final payerName = booking?.guestName ?? payment.revenueType;
      final paymentDate = _parseDateTime(payment.paymentDate);
      final bookingCode = booking != null
          ? _formatBookingCode(booking.id)
          : null;
      if (_isRoomPayment(payment.revenueType)) {
        totalRoomPaid += payment.amount;
      } else {
        totalOtherPaid += payment.amount;
      }
      if (booking != null) {
        relevantBookingIds.add(booking.id);
      }
      rows.add(
        _PaymentReportRow(
          paymentDate: paymentDate,
          amount: payment.amount,
          roomNumber: roomNumber,
          payerName: payerName,
          bookingId: booking?.id,
          bookingCode: bookingCode ?? 'غير متوفر',
          booking: booking,
          payment: payment,
        ),
      );
    }

    // حساب إجمالي المستحق والمتبقي باستخدام القيم المحسوبة الموثوقة من الحجز
    // (totalDueCached محسوب من تعديلات الأسعار + الخصومات الفعلية)
    // (remainingBalanceCached = totalDueCached - totalPaidCached)
    double totalDue = 0;
    double totalRemaining = 0;
    if (relevantBookingIds.isNotEmpty) {
      for (final bookingId in relevantBookingIds) {
        final booking = bookingMap[bookingId];
        if (booking == null) continue;
        totalDue += booking.totalDueCached;
        final remaining = booking.remainingBalanceCached;
        if (remaining > 0) {
          totalRemaining += remaining;
        }
      }
    }

    return _PaymentsReportResult(
      rows: rows,
      totalPaid: totalRoomPaid,
      totalOtherPaid: totalOtherPaid,
      totalRemaining: totalRemaining,
      totalDue: totalDue,
    );
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final selectedRoomLabel = _selectedRoom?.isNotEmpty == true
        ? _selectedRoom!
        : '';

    final dataRows = [
      for (final entry in _rows.asMap().entries)
        [
          (entry.key + 1).toString(),
          entry.value.bookingCode,
          entry.value.booking?.guestName ?? entry.value.payerName,
          entry.value.roomNumber,
          _translatePaymentMethod(entry.value.payment.paymentMethod),
          _dateLabelFormat.format(entry.value.paymentDate),
          EnhancedPdfUtils.formatNumber(entry.value.amount),
        ],
      [
        '',
        '',
        '',
        '',
        '',
        'الإجمالي',
        EnhancedPdfUtils.formatNumber(_totalPaid),
      ],
    ];

    await ReportPdfBuilder.buildAndShare(ReportPdfConfig(
      title: 'مدفوعات النزلاء',
      fromDate: _fromDate,
      toDate: _toDate,
      extraHeaderLine:
          selectedRoomLabel.isNotEmpty ? 'الغرفة: $selectedRoomLabel' : null,
      buildContent: (fonts) => [
        pw.SizedBox(height: 20),
        EnhancedPdfUtils.buildProfessionalTable(
          headers: [
            'م',
            'رقم الحجز',
            'اسم النزيل',
            'الغرفة',
            'طريقة الدفع',
            'التاريخ',
            'المبلغ',
          ],
          data: dataRows,
          fonts: fonts,
          headerColor: PdfColors.primary,
          alternateRowColor: PdfColors.backgroundLight,
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(16),
          decoration: pw.BoxDecoration(
            color: PdfColors.backgroundLight,
            border: pw.Border.all(color: PdfColors.primary, width: 0.5),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text(
                'الإجمالي الكلي: ',
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 12,
                  color: PdfColors.textDark,
                ),
              ),
              pw.Text(
                EnhancedPdfUtils.formatNumber(_totalPaid),
                style: pw.TextStyle(
                  font: fonts.bold,
                  fontSize: 14,
                  color: PdfColors.secondary,
                ),
              ),
            ],
          ),
        ),
      ],
      fileName: ReportPdfBuilder.generateFileName('مدفوعات النزلاء'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'تقرير دفوعات النزلاء',
      actions: [
        IconButton(
          icon: const Icon(Icons.picture_as_pdf),
          tooltip: 'تصدير PDF',
          onPressed: _rows.isEmpty ? null : _exportPdf,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // فلتر التاريخ المشترك
            ReportDateFilterWidget(
              controller: _filterController,
              onDateRangeChanged: (range) {
                setState(() {
                  _fromDate = range.from;
                  _toDate = range.to;
                });
                _fetchReport();
              },
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 140,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedRoom,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'الغرفة',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color),
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('الكل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color)),
                      ),
                      ..._availableRooms.map(
                        (room) => DropdownMenuItem<String?>(
                          value: room,
                          child: Text(room, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color)),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedRoom = value;
                      });
                    },
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search, size: 16),
                  label: Text(_loading ? 'جارٍ...' : 'بحث'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSummary(),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? const EmptyState(
                      title: 'لا توجد بيانات',
                      message: 'لم يتم العثور على دفوعات ضمن النطاق المحدد.',
                      icon: Icons.receipt_long,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 5),
                      itemBuilder: (context, index) {
                        final row = _rows[index];
                        return _buildPaymentCard(row);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentCard(_PaymentReportRow row) {
    return Card(
      elevation: 0.5,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _dateLabelFormat.format(row.paymentDate),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    color: Colors.grey,
                  ),
                ),
                Text(
                  _currencyFmt.format(row.amount),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.room, size: 13, color: Colors.blue),
                const SizedBox(width: 3),
                Text(
                  row.roomNumber,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.person, size: 13, color: Colors.grey),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    row.payerName,
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.payment, size: 13, color: Colors.grey),
                const SizedBox(width: 3),
                Text(
                  _translatePaymentMethod(row.payment.paymentMethod),
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const Spacer(),
                Text(
                  '#${row.bookingCode}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final totalAll = _totalPaid + _totalOtherPaid;
    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryTile(
                'مدفوعات الغرفة',
                _currencyFmt.format(_totalPaid),
                Colors.green,
              ),
            ),
            Container(width: 1, height: 28, color: Colors.grey.shade200),
            Expanded(
              child: _buildSummaryTile(
                'مدفوعات أخرى',
                _currencyFmt.format(_totalOtherPaid),
                Colors.teal,
              ),
            ),
            Container(width: 1, height: 28, color: Colors.grey.shade200),
            Expanded(
              child: _buildSummaryTile(
                'إجمالي المدفوعات',
                _currencyFmt.format(totalAll),
                Colors.indigo,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _translatePaymentMethod(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('cash') || normalized.contains('نقد')) {
      return 'نقداً';
    }
    if (normalized.contains('card') || normalized.contains('بطاق')) {
      return 'بطاقة';
    }
    if (normalized.contains('transfer') || normalized.contains('تحويل')) {
      return 'تحويل';
    }
    if (normalized.contains('check') || normalized.contains('شيك')) {
      return 'شيك';
    }
    return value;
  }

  /// هل الدفعة تُحسب ضمن رسوم الغرفة؟
  /// يجب أن يتطابق هذا المنطق مع _getTotalPayments في
  /// EnhancedBookingCalculationService لضمان تناسق المجاميع.
  static bool _isRoomPayment(String? revenueType) {
    if (revenueType == null || revenueType.isEmpty) return true;
    final r = revenueType.toLowerCase();
    return r == 'room' || r == 'غرفة' || r == 'إقامة';
  }

  Widget _buildSummaryTile(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }

  DateTime _parseDateTime(String value) {
    final normalized = value.contains('T')
        ? value
        : value.replaceFirst(' ', 'T');
    try {
      return DateTime.parse(normalized);
    } catch (_) {
      return DateTime.now();
    }
  }
}

class _PaymentReportRow {
  _PaymentReportRow({
    required this.paymentDate,
    required this.amount,
    required this.roomNumber,
    required this.payerName,
    required this.bookingId,
    required this.bookingCode,
    required this.booking,
    required this.payment,
  });

  final DateTime paymentDate;
  final double amount;
  final String roomNumber;
  final String payerName;
  final int? bookingId;
  final String bookingCode;
  final Booking? booking;
  final Payment payment;
}

class _PaymentsReportResult {
  _PaymentsReportResult({
    required this.rows,
    required this.totalPaid,
    required this.totalOtherPaid,
    required this.totalRemaining,
    required this.totalDue,
  });

  final List<_PaymentReportRow> rows;
  final double totalPaid;
  final double totalOtherPaid;
  final double totalRemaining;
  final double totalDue;
}
