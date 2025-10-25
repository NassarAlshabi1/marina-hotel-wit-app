import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../components/app_scaffold.dart';
import '../../components/widgets/empty_state.dart';
import '../../providers/core_providers.dart' as coreProviders;
import '../../services/local_db.dart';
import '../../utils/pdf_utils.dart';

class PaymentsReportScreen extends ConsumerStatefulWidget {
  const PaymentsReportScreen({super.key});

  @override
  ConsumerState<PaymentsReportScreen> createState() => _PaymentsReportScreenState();
}

class _PaymentsReportScreenState extends ConsumerState<PaymentsReportScreen> {
  final DateFormat _dateLabelFormat = DateFormat('yyyy/MM/dd HH:mm');
  final NumberFormat _currencyFmt = NumberFormat('#,##0.00', 'en_US');

  String _formatNumber(num value) => value.toStringAsFixed(0);

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _selectedRoom;
  bool _loading = false;
  bool _roomsLoaded = false;

  final List<_PaymentReportRow> _rows = [];
  final List<String> _availableRooms = [];

  double _totalPaid = 0;
  double _totalRemaining = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_roomsLoaded) {
      _roomsLoaded = true;
      _initializeDefaults();
    }
  }

  Future<void> _initializeDefaults() async {
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
    _toDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
    await _loadRooms();
    await _fetchReport();
  }

  Future<void> _loadRooms() async {
    final db = ref.read(coreProviders.dbProvider);
    final rooms = await db.select(db.rooms).get();
    setState(() {
      _availableRooms
        ..clear()
        ..addAll(rooms.map((e) => e.roomNumber).toList()..sort());
      if (_availableRooms.isNotEmpty && !_availableRooms.contains(_selectedRoom)) {
        _selectedRoom = null;
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initialDate = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = DateTime(picked.year, picked.month, picked.day, 0, 0, 0);
        } else {
          _toDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
        }
      });
    }
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
        _totalRemaining = result.totalRemaining;
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
    final payments = await (db.select(db.payments)).get();

    final bookingIds = payments.map((p) => p.bookingLocalId).whereType<int>().toSet();
    final bookings = bookingIds.isEmpty
        ? <Booking>[]
        : await (db.select(db.bookings)..where((tbl) => tbl.id.isIn(bookingIds))).get();
    final bookingMap = {for (final b in bookings) b.id: b};

    final roomNumbers = <String>{};
    for (final payment in payments) {
      final room = payment.roomNumber;
      if (room != null) roomNumbers.add(room);
      final bookingRoom = bookingMap[payment.bookingLocalId]?.roomNumber;
      if (bookingRoom != null) roomNumbers.add(bookingRoom);
    }
    final rooms = roomNumbers.isEmpty
        ? <Room>[]
        : await (db.select(db.rooms)..where((tbl) => tbl.roomNumber.isIn(roomNumbers.toList()))).get();
    final roomsMap = {for (final r in rooms) r.roomNumber: r};

    final filteredPayments = <Payment>[];
    for (final payment in payments) {
      final booking = bookingMap[payment.bookingLocalId];
      final candidateRoom = payment.roomNumber ?? booking?.roomNumber;
      final paymentDate = _parseDateTime(payment.paymentDate);
      if (_fromDate != null && paymentDate.isBefore(_fromDate!)) {
        continue;
      }
      if (_toDate != null && paymentDate.isAfter(_toDate!)) {
        continue;
      }
      if (_selectedRoom != null && _selectedRoom!.isNotEmpty && candidateRoom != _selectedRoom) {
        continue;
      }
      filteredPayments.add(payment);
    }

    filteredPayments.sort((a, b) {
      final aDate = _parseDateTime(a.paymentDate);
      final bDate = _parseDateTime(b.paymentDate);
      return bDate.compareTo(aDate);
    });

    final rows = <_PaymentReportRow>[];
    double totalPaid = 0;
    final relevantBookingIds = <int>{};

    for (final payment in filteredPayments) {
      final booking = bookingMap[payment.bookingLocalId];
      final roomNumber = payment.roomNumber ?? booking?.roomNumber ?? 'غير محدد';
      final payerName = booking?.guestName ?? payment.revenueType ?? 'غير محدد';
      final paymentDate = _parseDateTime(payment.paymentDate);
      totalPaid += payment.amount;
      if (booking != null) {
        relevantBookingIds.add(booking.id);
      }
      rows.add(_PaymentReportRow(
        paymentDate: paymentDate,
        amount: payment.amount,
        roomNumber: roomNumber,
        payerName: payerName,
        bookingId: booking?.id,
        booking: booking,
        payment: payment,
      ));
    }

    double totalRemaining = 0;
    if (relevantBookingIds.isNotEmpty) {
      final bookingTotals = <int, double>{};
      for (final bookingId in relevantBookingIds) {
        final booking = bookingMap[bookingId];
        if (booking == null) continue;
        final room = roomsMap[booking.roomNumber];
        final nights = booking.expectedNights > 0 ? booking.expectedNights : 1;
        final pricePerNight = room?.price ?? 0;
        bookingTotals[bookingId] = nights * pricePerNight;
      }

      final allPaymentsForBookings = await (db.select(db.payments)
            ..where((tbl) => tbl.bookingLocalId.isIn(relevantBookingIds.toList())))
          .get();
      final paidByBooking = <int, double>{};
      for (final p in allPaymentsForBookings) {
        final id = p.bookingLocalId;
        if (id == null) continue;
        paidByBooking[id] = (paidByBooking[id] ?? 0) + p.amount;
      }

      for (final entry in bookingTotals.entries) {
        final paid = paidByBooking[entry.key] ?? 0;
        final remaining = entry.value - paid;
        if (remaining > 0) {
          totalRemaining += remaining;
        }
      }
    }

    return _PaymentsReportResult(rows: rows, totalPaid: totalPaid, totalRemaining: totalRemaining);
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final fonts = await PdfUtils.loadArabicFonts();
    final logo = await PdfUtils.loadLogoImage();
    final doc = pw.Document();
    final fromLabel = _fromDate != null ? DateFormat('yyyy-MM-dd').format(_fromDate!) : 'غير محدد';
    final toLabel = _toDate != null ? DateFormat('yyyy-MM-dd').format(_toDate!) : 'غير محدد';
    final roomLabel = _selectedRoom?.isNotEmpty == true ? _selectedRoom! : 'كل الغرف';
    final summaryEntries = [
      MapEntry('إجمالي المدفوع', _formatNumber(_totalPaid)),
      MapEntry('الإجمالي المتبقي', _formatNumber(_totalRemaining)),
      MapEntry('عدد السجلات', _rows.length.toString()),
    ];

    final headers = ['التاريخ', 'المبلغ', 'الغرفة', 'اسم الدافع', 'طريقة الدفع'];
    final dataRows = _rows
        .map((row) => [
              _dateLabelFormat.format(row.paymentDate),
              _formatNumber(row.amount),
              row.roomNumber,
              row.payerName,
              row.payment.paymentMethod,
            ])
        .toList();

    pw.Widget buildSummaryTable() => pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: summaryEntries
              .map(
                (entry) => pw.TableRow(
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(entry.key, style: pw.TextStyle(font: fonts.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text(entry.value, style: pw.TextStyle(font: fonts.base)),
                    ),
                  ],
                ),
              )
              .toList(),
        );

    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: fonts.base, bold: fonts.bold),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(font: fonts.base, fontSize: 10),
          ),
        ),
        build: (context) {
          return [
            if (logo != null)
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Image(logo, width: 80),
              ),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('فندق مارينا بلازا', style: pw.TextStyle(font: fonts.bold, fontSize: 16)),
                  pw.Text('القاهرة - شارع احمد قاسم • رقم الهاتف 02324457', style: pw.TextStyle(font: fonts.base, fontSize: 8)),
                ],
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text('تقرير دفوعات النزلاء', style: pw.TextStyle(font: fonts.bold, fontSize: 20)),
            pw.SizedBox(height: 8),
            pw.Text('الفترة: من $fromLabel إلى $toLabel'),
            pw.Text('الغرفة: $roomLabel'),
            pw.SizedBox(height: 12),
            buildSummaryTable(),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: headers,
              headerStyle: pw.TextStyle(font: fonts.bold),
              cellStyle: pw.TextStyle(font: fonts.base),
              data: dataRows,
              cellAlignment: pw.Alignment.centerRight,
              border: pw.TableBorder.all(width: 0.5),
            ),
          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'payments-report.pdf');
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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDateSelector(label: 'من تاريخ', value: _fromDate, onPressed: () => _pickDate(isFrom: true)),
                _buildDateSelector(label: 'إلى تاريخ', value: _toDate, onPressed: () => _pickDate(isFrom: false)),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    value: _selectedRoom,
                    decoration: const InputDecoration(labelText: 'رقم الغرفة'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('كل الغرف'),
                      ),
                      ..._availableRooms.map(
                        (room) => DropdownMenuItem<String?>(
                          value: room,
                          child: Text(room),
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
                  onPressed: _loading ? null : _fetchReport,
                  icon: const Icon(Icons.search),
                  label: _loading ? const Text('جارٍ التحميل...') : const Text('عرض النتائج'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildSummary(),
            const SizedBox(height: 16),
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
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            return Card(
                              elevation: 1,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _dateLabelFormat.format(row.paymentDate),
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        Text('${_currencyFmt.format(row.amount)} ر.س'),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('الغرفة: ${row.roomNumber}'),
                                    const SizedBox(height: 4),
                                    Text('اسم الدافع: ${row.payerName}'),
                                    const SizedBox(height: 4),
                                    Text('طريقة الدفع: ${row.payment.paymentMethod}'),
                                    if (row.booking != null) ...[
                                      const SizedBox(height: 4),
                                      Text('رقم الحجز: ${row.booking!.id}'),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Card(
      color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(child: _buildSummaryTile('إجمالي المدفوع', _currencyFmt.format(_totalPaid))),
            Expanded(child: _buildSummaryTile('الإجمالي المتبقي', _currencyFmt.format(_totalRemaining))),
            Expanded(child: _buildSummaryTile('عدد السجلات', _rows.length.toString())),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value),
      ],
    );
  }

  Widget _buildDateSelector({required String label, required DateTime? value, required VoidCallback onPressed}) {
    final text = value != null ? DateFormat('yyyy-MM-dd').format(value) : 'غير محدد';
    return SizedBox(
      width: 180,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.date_range),
        label: Text('$label\n$text', textAlign: TextAlign.center),
      ),
    );
  }

  DateTime _parseDateTime(String value) {
    final normalized = value.contains('T') ? value : value.replaceFirst(' ', 'T');
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
    required this.booking,
    required this.payment,
  });

  final DateTime paymentDate;
  final double amount;
  final String roomNumber;
  final String payerName;
  final int? bookingId;
  final Booking? booking;
  final Payment payment;
}

class _PaymentsReportResult {
  _PaymentsReportResult({required this.rows, required this.totalPaid, required this.totalRemaining});

  final List<_PaymentReportRow> rows;
  final double totalPaid;
  final double totalRemaining;
}
