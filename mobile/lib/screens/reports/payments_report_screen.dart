import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../components/widgets/empty_state.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/daos/payments_dao.dart';
import '../../services/local_db.dart';
import '../../utils/enhanced_pdf_utils.dart';
import '../../utils/hotel_time_engine.dart';
import '../../utils/report_pdf_builder.dart';
import '../../widgets/report_date_filter.dart';
import 'report_page_scaffold.dart';

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
  double _totalRemaining = 0;
  double _totalDue = 0;
  List<_BookingSummary> _bookingSummaries = [];

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
    final range = DateFilterController.getDefaultHotelDayRange();
    _fromDate = range.from;
    _toDate = range.to;
    await _loadRooms();
    // تحديث القيم المحسوبة (totalDueCached, totalPaidCached, remainingBalanceCached)
    // لضمان دقة المجاميع في التقرير
    try {
      final db = ref.read(databaseProvider);
      final derivedService = BookingDerivedFieldsService(db);
      await derivedService.refreshAllActiveBookings();
    } catch (_) {}
    await _fetchReport();
  }

  Future<void> _loadRooms() async {
    final db = ref.read(databaseProvider);
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
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final db = ref.read(databaseProvider);
      final result = await _loadPaymentsReport(db);
      setState(() {
        _rows
          ..clear()
          ..addAll(result.rows);
        _totalPaid = result.totalPaid;
        _totalOtherPaid = result.totalOtherPaid;
        _totalRemaining = result.totalRemaining;
        _totalDue = result.totalDue;
        _bookingSummaries
          ..clear()
          ..addAll(result.bookingSummaries);
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

    // ✅ إصلاح: استخدام hotelDayKey للفلترة بدلاً من مقارنة paymentDate كنص
    // مقارنة النصوص "2026-05-18 10:30:00" >= "2026-05-18 14:00:00" تُعطي نتائج خاطئة
    // لأن الساعة 10:30 أقل من 14:00 لكن المقارنة النصية تعتبرها أكبر!
    // hotelDayKey يُخزن كـ "yyyy-MM-dd" دائماً فيُحسب من قاعدة الساعة 14:00 تلقائياً
    final fromHotelDay = HotelTimeEngine.getHotelDayKey(
        dateTime: _fromDate!.add(const Duration(seconds: 1)));
    final toHotelDay = HotelTimeEngine.getHotelDayKey(dateTime: _toDate!);

    // استخدام listByHotelDayKey للفلترة الدقيقة
    final payments = await paymentsDao.listFilteredByHotelDay(
      fromHotelDay: fromHotelDay,
      toHotelDay: toHotelDay,
      excludeVoided: true,
      excludePendingBalance: true,
    );
    // فلترة حسب الغرفة في الذاكرة إذا تم اختيار غرفة محددة
    final filteredPayments = _selectedRoom != null && _selectedRoom!.isNotEmpty
        ? payments.where((p) => p.roomNumber == _selectedRoom).toList()
        : payments;

    final bookingIds = filteredPayments
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
    for (final payment in filteredPayments) {
      final room = payment.roomNumber;
      if (room != null) {
        roomNumbers.add(room);
      }
      final bookingRoom = bookingMap[payment.bookingLocalId]?.roomNumber;
      if (bookingRoom != null) {
        roomNumbers.add(bookingRoom);
      }
    }
    // جلب أسعار الغرف الأصلية لعرضها في التقرير
    final roomPriceMap = <String, double>{};
    if (roomNumbers.isNotEmpty) {
      final rooms = await (db.select(db.rooms)
            ..where((r) => r.roomNumber.isIn(roomNumbers.toList())))
          .get();
      for (final room in rooms) {
        roomPriceMap[room.roomNumber] = room.price;
      }
    }

    final rows = <_PaymentReportRow>[];
    double totalRoomPaid = 0;
    double totalOtherPaid = 0;
    final relevantBookingIds = <int>{};

    for (final payment in filteredPayments) {
      // ✅ استبعاد المدفوعات الملغاة والمعلقة من الإجمالي
      if (payment.isVoided || payment.isPendingBalance) continue;
      final paymentDate = _parseDateTime(payment.paymentDate);
      
      // ✅ تمت الفلترة بـ hotelDayKey على مستوى DB — لا حاجة لفلترة إضافية بالتاريخ

      final booking = bookingMap[payment.bookingLocalId];
      final roomNumber =
          booking?.roomNumber ?? payment.roomNumber ?? 'غير محدد';
      final payerName = booking?.guestName ?? payment.revenueType;
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
        if (booking == null) {
          continue;
        }
        totalDue += booking.totalDueCached;
        final remaining = booking.remainingBalanceCached;
        if (remaining > 0) {
          totalRemaining += remaining;
        }
      }
    }

    // بناء ملخص الحجوزات مع سعر الغرفة والخصم والمتبقي
    final bookingSummaries = <_BookingSummary>[];
    for (final bookingId in relevantBookingIds) {
      final booking = bookingMap[bookingId];
      if (booking == null) continue;

      final roomPrice = roomPriceMap[booking.roomNumber] ?? 0;
      final nights = booking.calculatedNights > 0 ? booking.calculatedNights : 1;
      final effectivePricePerNight = booking.totalDueCached / nights;

      bookingSummaries.add(_BookingSummary(
        bookingId: booking.id,
        bookingCode: _formatBookingCode(booking.id),
        guestName: booking.guestName,
        roomNumber: booking.roomNumber,
        nights: nights,
        roomPricePerNight: roomPrice,
        discount: booking.discount,
        discountType: booking.discountType,
        totalDue: booking.totalDueCached,
        totalPaid: booking.totalPaidCached,
        remainingBalance: booking.remainingBalanceCached,
        effectivePricePerNight: effectivePricePerNight,
      ));
    }

    return _PaymentsReportResult(
      rows: rows,
      totalPaid: totalRoomPaid,
      totalOtherPaid: totalOtherPaid,
      totalRemaining: totalRemaining,
      totalDue: totalDue,
      bookingSummaries: bookingSummaries,
    );
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) {
      return;
    }
    final selectedRoomLabel = _selectedRoom?.isNotEmpty ?? false
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
        // ─── ملخص الحجوزات: سعر الغرفة والخصم والمتبقي ───
        if (_bookingSummaries.isNotEmpty) ...[
          pw.SizedBox(height: 24),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 14),
            decoration: pw.BoxDecoration(
              color: PdfColors.accent,
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              'ملخص الحجوزات - سعر الغرفة والخصم والمتبقي',
              style: pw.TextStyle(
                font: fonts.bold,
                fontSize: 14,
                color: PdfColors.textWhite,
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 10),
          EnhancedPdfUtils.buildProfessionalTable(
            headers: [
              'النزيل',
              'الغرفة',
              'الليالي',
              'سعر الليلة',
              'الخصم',
              'بعد الخصم',
              'المستحق',
              'المدفوع',
              'المتبقي',
            ],
            data: [
              for (final s in _bookingSummaries)
                [
                  s.guestName,
                  s.roomNumber,
                  s.nights.toString(),
                  EnhancedPdfUtils.formatNumber(s.roomPricePerNight),
                  s.discount > 0
                      ? '${EnhancedPdfUtils.formatNumber(s.discount)}${s.discountType == 'total' ? ' (إجمالي)' : ' (لليلة)'}'
                      : '-',
                  EnhancedPdfUtils.formatNumber(s.effectivePricePerNight),
                  EnhancedPdfUtils.formatNumber(s.totalDue),
                  EnhancedPdfUtils.formatNumber(s.totalPaid),
                  EnhancedPdfUtils.formatNumber(s.remainingBalance),
                ],
            ],
            fonts: fonts,
            headerColor: PdfColors.accent,
            alternateRowColor: PdfColors.backgroundLight,
          ),
          pw.SizedBox(height: 14),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              color: PdfColors.backgroundLight,
              border: pw.Border.all(
                color: _totalRemaining > 0 ? PdfColors.danger : PdfColors.success,
                width: 1,
              ),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'إجمالي المتبقي على النزلاء:',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 14,
                    color: PdfColors.textDark,
                  ),
                ),
                pw.Text(
                  '${EnhancedPdfUtils.formatNumber(_totalRemaining)} ريال',
                  style: pw.TextStyle(
                    font: fonts.bold,
                    fontSize: 18,
                    color: _totalRemaining > 0 ? PdfColors.danger : PdfColors.success,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      fileName: ReportPdfBuilder.generateFileName('مدفوعات النزلاء'),
    ),);
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: 'تقرير دفوعات النزلاء',
      filterController: _filterController,
      onDateRangeChanged: (range) {
        setState(() {
          _fromDate = range.from;
          _toDate = range.to;
        });
        _fetchReport();
      },
      onExportPdf: _exportPdf,
      onSearch: _fetchReport,
      isPdfEnabled: _rows.isNotEmpty,
      isLoading: _loading,
      filterWidgets: [
        SizedBox(
          width: 140,
          child: DropdownButtonFormField<String?>(
            initialValue: _selectedRoom,
            decoration: const InputDecoration(
              labelText: 'الغرفة',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            ),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).textTheme.bodyMedium?.color),
            items: [
              DropdownMenuItem<String?>(
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
              _fetchReport();
            },
          ),
        ),
      ],
      summaryWidget: _buildSummary(),
      contentWidget: _loading
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
              separatorBuilder: (_, _) => const SizedBox(height: 5),
              itemBuilder: (context, index) {
                final row = _rows[index];
                return _buildPaymentCard(row);
              },
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
    final isRoomSelected = _selectedRoom != null && _selectedRoom!.isNotEmpty;

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            // ─── تفاصيل الغرفة المحددة ───
            if (isRoomSelected && _bookingSummaries.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200, width: 0.5),
                ),
                child: Column(
                  children: [
                    for (final s in _bookingSummaries) ...[
                      _buildDetailRow('سعر الليلة (بدون خصم)', '${_currencyFmt.format(s.roomPricePerNight)} ريال'),
                      if (s.discount > 0) ...[
                        _buildDetailRow(
                          'الخصم',
                          '${_currencyFmt.format(s.discount)} ريال ${s.discountType == 'total' ? '(إجمالي)' : '(لليلة)'}',
                          valueColor: Colors.green,
                        ),
                      ],
                      _buildDetailRow('سعر الليلة بعد الخصم', '${_currencyFmt.format(s.effectivePricePerNight)} ريال'),
                      _buildDetailRow('عدد الليالي', '${s.nights}'),
                      const Divider(height: 10, thickness: 0.5),
                      _buildDetailRow('إجمالي المستحق', '${_currencyFmt.format(s.totalDue)} ريال', valueColor: Colors.blue),
                      _buildDetailRow('إجمالي المدفوع', '${_currencyFmt.format(s.totalPaid)} ريال', valueColor: Colors.green),
                      _buildDetailRow(
                        'المبلغ المتبقي',
                        '${_currencyFmt.format(s.remainingBalance)} ريال',
                        valueColor: s.remainingBalance > 0 ? Colors.red : Colors.green,
                        isBold: true,
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 16),
            ],

            // ─── المجاميع العامة ───
            Row(
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
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryTile(
                    'إجمالي المستحق',
                    _currencyFmt.format(_totalDue),
                    Colors.blue,
                  ),
                ),
                Container(width: 1, height: 28, color: Colors.grey.shade200),
                Expanded(
                  child: _buildSummaryTile(
                    'المتبقي على النزلاء',
                    _currencyFmt.format(_totalRemaining),
                    _totalRemaining > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            _buildSummaryTile(
              'إجمالي المدفوعات (الدخل)',
              _currencyFmt.format(totalAll),
              Colors.indigo,
              isLarge: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ],
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
    if (revenueType == null || revenueType.isEmpty) {
      return true;
    }
    final r = revenueType.toLowerCase();
    return r == 'room' || r == 'غرفة' || r == 'إقامة';
  }

  Widget _buildSummaryTile(String label, String value, Color color, {bool isLarge = false}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold, 
            fontSize: isLarge ? 18 : 13, 
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: isLarge ? 12 : 10, 
            color: isLarge ? Colors.black87 : Colors.grey,
            fontWeight: isLarge ? FontWeight.bold : FontWeight.normal,
          ),
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
    required this.bookingSummaries,
  });

  final List<_PaymentReportRow> rows;
  final double totalPaid;
  final double totalOtherPaid;
  final double totalRemaining;
  final double totalDue;
  final List<_BookingSummary> bookingSummaries;
}

class _BookingSummary {
  _BookingSummary({
    required this.bookingId,
    required this.bookingCode,
    required this.guestName,
    required this.roomNumber,
    required this.nights,
    required this.roomPricePerNight,
    required this.discount,
    required this.discountType,
    required this.totalDue,
    required this.totalPaid,
    required this.remainingBalance,
    required this.effectivePricePerNight,
  });

  final int bookingId;
  final String bookingCode;
  final String guestName;
  final String roomNumber;
  final int nights;
  final double roomPricePerNight;
  final double discount;
  final String discountType;
  final double totalDue;
  final double totalPaid;
  final double remainingBalance;
  final double effectivePricePerNight;
}
