import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';
import '../../services/local_db.dart' as db;
import '../../utils/message_templates.dart';
import '../../models/payment_models.dart';
import '../../components/widgets/payment_widgets.dart';
import '../../providers/repository_providers.dart';
import '../../utils/time.dart';
import 'payment_history_screen.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../services/screen_sync_controller.dart';

const List<PaymentMethod> _allowedPaymentMethods = [
  PaymentMethod.cash,
  PaymentMethod.transfer,
];

class BookingPaymentScreen extends ConsumerStatefulWidget {
  final db.Booking booking;
  
  const BookingPaymentScreen({
    super.key,
    required this.booking,
  });

  @override
  ConsumerState<BookingPaymentScreen> createState() => _BookingPaymentScreenState();
}

class _BookingPaymentScreenState extends ConsumerState<BookingPaymentScreen>
    with SingleTickerProviderStateMixin, SyncOnExitMixin {
  
  @override
  String get screenId => 'booking_payment';
  late TabController _tabController;
  late TextEditingController _phoneController;
  final _currencyFmt = NumberFormat('#,##0', 'en_US');
  double _remainingAmount = 0;
  late String _currentGuestPhone;
  int? _expectedNightsOverride;
  DateTime? _plannedCheckoutOverride;
  String? _bookingNotesOverride;

  Payment _mapDbPaymentToUi(db.Payment p) {
    return Payment(
      id: p.localUuid,
      bookingId: widget.booking.localUuid,
      amount: p.amount,
      method: _mapDbMethodToUi(p.paymentMethod),
      status: PaymentStatus.completed,
      paymentDate: DateTime.tryParse(p.paymentDate) ?? DateTime.now(),
      notes: p.notes,
      receivedBy: 'admin',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  PaymentMethod _mapDbMethodToUi(String m) {
    switch (m) {
      case 'نقدي':
        return PaymentMethod.cash;
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return PaymentMethod.card;
      case 'تحويل':
      case 'تحويل بنكي':
        return PaymentMethod.transfer;
      case 'شيك':
        return PaymentMethod.check;
      case 'تقسيط':
        return PaymentMethod.installment;
      default:
        return PaymentMethod.cash;
    }
  }

  String _mapUiMethodToDb(PaymentMethod m) {
    switch (m) {
      case PaymentMethod.cash:
        return 'نقدي';
      case PaymentMethod.card:
        return 'بطاقة';
      case PaymentMethod.transfer:
        return 'تحويل';
      case PaymentMethod.check:
        return 'شيك';
      case PaymentMethod.installment:
        return 'تقسيط';
    }
  }

  String _cleanAndFormatPhone(String phone) {
    var digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.isEmpty) {
      return '';
    }
    if (digitsOnly.startsWith('00')) {
      digitsOnly = digitsOnly.substring(2);
    }
    if (digitsOnly.startsWith('07')) {
      digitsOnly = '967${digitsOnly.substring(1)}';
    } else if (digitsOnly.startsWith('5') && digitsOnly.length == 9) {
      digitsOnly = '966$digitsOnly';
    }
    return digitsOnly;
  }

  DateTime? _resolvePlannedCheckout() {
    if (_plannedCheckoutOverride != null) {
      return _plannedCheckoutOverride;
    }
    if (widget.booking.checkoutDate != null) {
      return DateTime.tryParse(widget.booking.checkoutDate!);
    }
    return null;
  }

  int _resolveExpectedNights(DateTime checkin, DateTime? plannedCheckout) {
    if (_expectedNightsOverride != null) {
      return _expectedNightsOverride!;
    }
    if (widget.booking.expectedNights > 0) {
      return widget.booking.expectedNights;
    }
    return Time.nightsWithCutoff(checkin, checkout: plannedCheckout);
  }

  String _formatDateOnly(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _phoneController = TextEditingController(text: widget.booking.guestPhone);
    _phoneController.addListener(markDataChanged);
    _currentGuestPhone = widget.booking.guestPhone;
  }

  @override
  void dispose() {
    _phoneController.removeListener(markDataChanged);
    _tabController.dispose();
    _phoneController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final roomsRepo = ref.watch(roomsRepoProvider);
    final paymentsRepo = ref.watch(paymentsRepoProvider);

    return wrapWithSyncOnExit(
      child: AppScaffold(
        title: 'معالجة المدفوعات',
      actions: [
        IconButton(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PaymentHistoryScreen(bookingId: widget.booking.localUuid),
            ),
          ),
          icon: const Icon(Icons.history),
          tooltip: 'سجل المدفوعات',
        ),
      ],
      body: StreamBuilder<db.Room?>(
        stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
        builder: (context, roomSnap) {
          final roomRate = roomSnap.data?.price ?? 0.0;
          final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
          final plannedCheckout = _resolvePlannedCheckout();
          final actualCheckout = widget.booking.actualCheckout != null ? DateTime.tryParse(widget.booking.actualCheckout!) : null;
          final expectedNights = _resolveExpectedNights(checkin, plannedCheckout);
          final actualNights = Time.nightsWithCutoff(checkin, checkout: actualCheckout ?? DateTime.now());
          
          // التكلفة الإجمالية = الليالي الفعلية × سعر الليلة (وليس المتوقعة)
          final totalAmount = actualNights * roomRate;
          debugPrint('BookingPaymentScreen: booking.id=${widget.booking.id}, booking.localUuid=${widget.booking.localUuid}');
          return StreamBuilder<List<db.Payment>>(
            stream: paymentsRepo.paymentsByBooking(widget.booking.id),
            builder: (context, paySnap) {
              final dbPayments = paySnap.data ?? const <db.Payment>[];
              debugPrint('BookingPaymentScreen: StreamBuilder received ${dbPayments.length} payments');
              final paidAmount = dbPayments.fold<double>(0, (s, p) => s + p.amount);
              final remainingAmount = ((totalAmount - paidAmount).clamp(0.0, totalAmount)).toDouble();
              _remainingAmount = remainingAmount;
              final uiPayments = dbPayments.map(_mapDbPaymentToUi).toList();
              final summary = BookingPaymentSummary(
                bookingId: widget.booking.localUuid,
                totalAmount: totalAmount,
                paidAmount: paidAmount,
                remainingAmount: remainingAmount,
                payments: uiPayments,
                overallStatus: remainingAmount <= 0 ? PaymentStatus.completed : PaymentStatus.pending,
              );

              return Column(
                children: [
                  _buildPaymentSummaryCard(
                    summary,
                    roomRate: roomRate,
                    expectedNights: expectedNights,
                    actualNights: actualNights,
                    checkin: checkin,
                    plannedCheckout: plannedCheckout,
                    actualCheckout: actualCheckout,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Theme.of(context).colorScheme.onPrimary,
                      unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: 'دفعة جديدة'),
                        Tab(text: 'الإجراءات'),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildNewPaymentTab(summary),
                        _buildActionsTab(summary),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(
    BookingPaymentSummary summary, {
    required double roomRate,
    required int expectedNights,
    required int actualNights,
    required DateTime checkin,
    DateTime? plannedCheckout,
    DateTime? actualCheckout,
  }) {
    final progressPercentage = summary.paidPercentage / 100;
    final dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'en');
    final checkinText = dateFmt.format(checkin);
    final plannedText = plannedCheckout != null ? dateFmt.format(plannedCheckout) : null;
    final actualText = actualCheckout != null ? dateFmt.format(actualCheckout) : null;
    final hasPhone = _currentGuestPhone.isNotEmpty;
    final identityLine = widget.booking.guestIdNumber.isEmpty
        ? widget.booking.guestIdType
        : '${widget.booking.guestIdType} • ${widget.booking.guestIdNumber}';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            summary.isFullyPaid ? Colors.green.shade50 : Colors.blue.shade50,
            summary.isFullyPaid ? Colors.green.shade100 : Colors.blue.shade100,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: summary.isFullyPaid ? Colors.green.shade200 : Colors.blue.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blue,
                child: Text(
                  widget.booking.roomNumber,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.booking.guestName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'غرفة ${widget.booking.roomNumber}${hasPhone ? ' • $_currentGuestPhone' : ''}',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(identityLine, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    Text('الجنسية: ${widget.booking.guestNationality}', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    Text('الوصول: $checkinText', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    if (plannedText != null)
                      Text('المغادرة المخطط: $plannedText', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    if (actualText != null)
                      Text('المغادرة الفعلي: $actualText', style: const TextStyle(fontSize: 13, color: Colors.green)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: summary.isFullyPaid
                      ? Colors.green.withOpacity(0.2)
                      : Colors.orange.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: summary.isFullyPaid ? Colors.green : Colors.orange,
                  ),
                ),
                child: Text(
                  summary.isFullyPaid ? 'مكتمل الدفع' : 'دفع جزئي',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: summary.isFullyPaid ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDetailChip(
                context,
                icon: Icons.attach_money,
                label: 'سعر الليلة',
                value: '${_currencyFmt.format(roomRate)}',
              ),
              _buildDetailChip(
                context,
                icon: Icons.nightlight_round,
                label: 'الليالي المتوقعة',
                value: expectedNights.toString(),
              ),
              _buildDetailChip(
                context,
                icon: Icons.task_alt,
                label: 'الليالي الفعلية',
                value: actualNights.toString(),
                color: actualNights > expectedNights ? Colors.orange : Colors.green,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تقدم الدفع',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${summary.paidPercentage.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progressPercentage,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    summary.isFullyPaid ? Colors.green : Colors.blue,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Expanded(child: _buildAmountChip('الإجمالي', summary.totalAmount, Colors.blue)),
              const SizedBox(width: 8),
              Expanded(child: _buildAmountChip('المدفوع', summary.paidAmount, Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _buildAmountChip('المتبقي', summary.remainingAmount, Colors.red)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            '${_currencyFmt.format(amount)}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    Color? color,
  }) {
    final chipColor = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: chipColor.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: chipColor, fontWeight: FontWeight.bold, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(color: chipColor, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNewPaymentTab(BookingPaymentSummary summary) {
    if (summary.isFullyPaid) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 80,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
            const Text(
              'تم سداد المبلغ كاملاً',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'يمكنك الآن تسجيل مغادرة العميل',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إضافة دفعة جديدة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // نموذج إضافة الدفعة
          _buildPaymentForm(summary),
        ],
      ),
    );
  }

  Widget _buildPaymentForm(BookingPaymentSummary summary) {
    return Column(
      children: [
        const Align(
          alignment: Alignment.centerRight,
          child: Text('رقم الهاتف', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'رقم هاتف النزيل',
            border: OutlineInputBorder(),
          ),
          textDirection: ui.TextDirection.ltr,
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('طريقة الدفع', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 2.5,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: _allowedPaymentMethods.length,
          itemBuilder: (context, index) {
            final method = _allowedPaymentMethods[index];
            return _buildPaymentMethodCard(method);
          },
        ),
        const SizedBox(height: 20),
        const Align(
          alignment: Alignment.centerRight,
          child: Text('دفعات سريعة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildQuickPaymentButton('25%', summary.remainingAmount * 0.25, summary)),
            const SizedBox(width: 8),
            Expanded(child: _buildQuickPaymentButton('50%', summary.remainingAmount * 0.5, summary)),
            const SizedBox(width: 8),
            Expanded(child: _buildQuickPaymentButton('75%', summary.remainingAmount * 0.75, summary)),
            const SizedBox(width: 8),
            Expanded(child: _buildQuickPaymentButton('100%', summary.remainingAmount, summary)),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentMethodCard(PaymentMethod method) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: () => _showPaymentDialog(method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: method.color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(method.icon, color: method.color, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  method.displayName,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: method.color,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPaymentButton(String label, double amount, BookingPaymentSummary summary) {
    return ElevatedButton(
      onPressed: amount > 0 ? () => _showPaymentDialog(PaymentMethod.cash, amount) : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${_currencyFmt.format(amount)}', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActionsTab(BookingPaymentSummary summary) {
    final checkoutDate = _plannedCheckoutOverride ?? (widget.booking.checkoutDate != null ? DateTime.tryParse(widget.booking.checkoutDate!) : null);
    final checkoutDisplay = checkoutDate != null ? _formatDateOnly(checkoutDate) : null;
    final bookingNotes = _bookingNotesOverride ?? widget.booking.notes;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإجراءات المتاحة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          
          // إجراءات المدفوعات
          _buildActionCard(
            'عرض الفاتورة الشاملة',
            'عرض وطباعة الفاتورة التفصيلية',
            Icons.receipt_long,
            Colors.blue,
            () => _generateInvoice(summary),
          ),
          
          _buildActionCard(
            'سجل المدفوعات',
            'عرض تاريخ جميع المدفوعات',
            Icons.history,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PaymentHistoryScreen(bookingId: widget.booking.localUuid),
              ),
            ),
          ),
          
          _buildActionCard(
            'تسجيل المغادرة',
            summary.isFullyPaid
                ? 'تسجيل مغادرة العميل وتحرير الغرفة'
                : 'سيتم نقل المتبقي (${_currencyFmt.format(summary.remainingAmount)}) إلى الديون تلقائياً وتحرير الغرفة',
            Icons.logout,
            summary.isFullyPaid ? Colors.green : Colors.orange,
            () => _handleCheckout(summary),
          ),
          
          _buildActionCard(
            'إرسال كشف حساب',
            'إرسال ملخص المدفوعات للعميل',
            Icons.send,
            Colors.orange,
            () => _sendAccountStatement(summary),
          ),
          
          const SizedBox(height: 20),
          
          // معلومات الحجز
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'معلومات الحجز',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow('رقم الحجز', widget.booking.localUuid),
                  _buildInfoRow('تاريخ الوصول', widget.booking.checkinDate.split(' ')[0]),
                  if (checkoutDisplay != null)
                    _buildInfoRow('تاريخ المغادرة', checkoutDisplay),
                  _buildInfoRow('الحالة', widget.booking.status),
                  if (bookingNotes != null && bookingNotes.isNotEmpty)
                    _buildInfoRow('ملاحظات', bookingNotes),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback? onTap, {
    bool enabled = true,
  }) {
    final effectiveColor = enabled ? color : Colors.grey;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: effectiveColor.withOpacity(0.2),
          child: Icon(icon, color: effectiveColor),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: enabled ? null : Colors.grey.shade600),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: enabled ? null : Colors.grey,
        ),
        onTap: enabled ? onTap : null,
        enabled: enabled,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  void _showPaymentDialog(PaymentMethod method, [double? presetAmount]) {
    final amountController = TextEditingController(
      text: presetAmount?.toStringAsFixed(0) ?? '',
    );
    final notesController = TextEditingController();
    final referenceController = TextEditingController();
    final cardDigitsController = TextEditingController();
    final bankController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(method.icon, color: method.color),
              const SizedBox(width: 8),
              Text('دفع ${method.displayName}'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'المبلغ*',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // حقول إضافية حسب طريقة الدفع
                  if (method == PaymentMethod.card) ...[
                    TextField(
                      controller: cardDigitsController,
                      decoration: const InputDecoration(
                        labelText: 'آخر 4 أرقام من البطاقة',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  if (method == PaymentMethod.transfer) ...[
                    TextField(
                      controller: bankController,
                      decoration: const InputDecoration(
                        labelText: 'اسم البنك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  if (method == PaymentMethod.transfer || method == PaymentMethod.check) ...[
                    TextField(
                      controller: referenceController,
                      decoration: const InputDecoration(
                        labelText: 'رقم المرجع/الشيك',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => _processPayment(
                method,
                amountController.text,
                notesController.text,
                referenceController.text,
                cardDigitsController.text,
                bankController.text,
              ),
              child: const Text('تسجيل الدفعة'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String> _buildMessage({
    required double amount,
    required double remaining,
    int addedNights = 0,
    DateTime? newCheckout,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final template = prefs.getString('whatsapp_template') ?? whatsappPaymentTemplate;

    String formatAmount(double value) {
      if (value == value.toInt()) return '${value.toInt()}';
      return _currencyFmt.format(value);
    }

    String message = template
        .replaceAll('{name}', widget.booking.guestName)
        .replaceAll('{amount}', formatAmount(amount))
        .replaceAll('{room}', widget.booking.roomNumber)
        .replaceAll('{remaining}', formatAmount(remaining));

    if (addedNights > 0) {
      final extraNightsText = 'تم تمديد الإقامة تلقائياً بـ $addedNights ${addedNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}';
      message = message.replaceAll('{extra_nights}', extraNightsText);
    } else {
      message = message.replaceAll('{extra_nights}', '');
    }

    if (newCheckout != null) {
      final checkoutText = 'تاريخ المغادرة الجديد: ${newCheckout.day}/${newCheckout.month}/${newCheckout.year}';
      message = message.replaceAll('{new_checkout}', checkoutText);
    } else {
      message = message.replaceAll('{new_checkout}', '');
    }

    // Clean up empty lines potentially left by removed placeholders
    return message.replaceAll(RegExp(r'\n\s*\n'), '\n').trim();
  }

  Future<void> _sendPaymentConfirmation(
    double amountPaidNow,
    double remaining,
    String cleanedPhone, {
    int addedNights = 0,
    DateTime? newCheckout,
  }) async {
    if (cleanedPhone.isEmpty) {
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);

    final message = await _buildMessage(
      amount: amountPaidNow,
      remaining: remaining,
      addedNights: addedNights,
      newCheckout: newCheckout,
    );

    try {
      await whatsappService.sendMessage(
        phoneE164: cleanedPhone,
        message: message,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')),
        );
      }
    }
  }

  /// التحقق من وجود ليالي إضافية
  bool _shouldShowExtendedStayOptions(BookingPaymentSummary summary) {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = Time.nightsWithCutoff(checkin, checkout: now);
    final plannedCheckout = _resolvePlannedCheckout();
    final expectedNights = _resolveExpectedNights(checkin, plannedCheckout);

    // عرض خيارات الليالي الإضافية إذا:
    // 1. الليالي الحالية أكثر من المتوقعة
    // 2. أو إذا كان اليوم الحالي بعد تاريخ المغادرة المخطط
    final isPastCheckoutDate = plannedCheckout != null && now.isAfter(plannedCheckout);

    return currentStay > expectedNights || isPastCheckoutDate;
  }

  /// عرض خيارات دفع الليالي الإضافية
  Widget _buildExtendedStayPaymentOptions(BookingPaymentSummary summary) {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final now = DateTime.now();
    final currentStay = Time.nightsWithCutoff(checkin, checkout: now);
    final plannedCheckout = _resolvePlannedCheckout();
    final expectedNights = _resolveExpectedNights(checkin, plannedCheckout);
    final extraNights = currentStay - expectedNights;
    
    if (extraNights <= 0) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Column(
          children: [
            Icon(Icons.access_time, color: Colors.blue, size: 32),
            const SizedBox(height: 8),
            Text(
              'خيارات تمديد الإقامة ستظهر عند تجاوز الليالي المخططة',
              style: TextStyle(color: Colors.blue.shade700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                'إقامة ممددة - $extraNights ليلة إضافية',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // دفع سريع للليالي الإضافية
          Row(
            children: [
              Expanded(
                child: _buildDailyPaymentButton(
                  'دفع ليلة واحدة', 
                  summary, 
                  1,
                ),
              ),
              const SizedBox(width: 8),
              if (extraNights >= 2) ...[
                Expanded(
                  child: _buildDailyPaymentButton(
                    'دفع ليلتين', 
                    summary, 
                    2,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: _buildDailyPaymentButton(
                  'دفع كل الإضافي ($extraNights)', 
                  summary, 
                  extraNights,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// زر دفع سريع للليالي الإضافية
  Widget _buildDailyPaymentButton(String label, BookingPaymentSummary summary, int nights) {
    final roomsRepo = ref.watch(roomsRepoProvider);
    
    return StreamBuilder<db.Room?>(
      stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
      builder: (context, roomSnap) {
        final roomRate = roomSnap.data?.price ?? 0.0;
        final amount = nights * roomRate;
        
        return ElevatedButton(
          onPressed: amount > 0 ? () => _showDailyPaymentDialog(nights, amount) : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Column(
            children: [
              Text(
                label, 
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              Text(
                '${_currencyFmt.format(amount)}', 
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        );
      }
    );
  }

  /// نافذة دفع الليالي اليومية
  void _showDailyPaymentDialog(int nights, double amount) {
    final notesController = TextEditingController(
      text: nights == 1 
        ? 'دفع ليلة إضافية واحدة'
        : 'دفع $nights ليالي إضافية',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.hotel, color: Colors.orange),
            const SizedBox(width: 8),
            Text('دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Text('المبلغ: ${_currencyFmt.format(amount)}'),
                  Text('عدد الليالي: $nights'),
                  Text('سعر الليلة: ${_currencyFmt.format(amount / nights)}'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'ملاحظات',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => _processDailyPayment(amount, notesController.text, nights),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('تسجيل الدفعة'),
          ),
        ],
      ),
    );
  }

  /// معالجة دفع الليالي الإضافية
  Future<void> _processDailyPayment(double amount, String notes, int nights) async {
    final paymentsRepo = ref.read(paymentsRepoProvider);
    
    try {
      final paymentId = await paymentsRepo.create(
        bookingLocalId: widget.booking.id,
        roomNumber: widget.booking.roomNumber,
        amount: amount,
        paymentDate: Time.nowIso(),
        notes: notes.isEmpty ? 'دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية' : notes,
        paymentMethod: 'نقدي',
        revenueType: 'room',
      );
      
      if (paymentId <= 0) {
        throw Exception('فشل في إنشاء الدفعة');
      }
      
      markDataChanged();
      
      final roomsRepo = ref.read(roomsRepoProvider);
      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      final roomRate = room?.price ?? 0.0;
      final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
      final now = DateTime.now();
      final currentNights = Time.nightsWithCutoff(checkin, checkout: now);
      final currentTotal = currentNights * roomRate;
      final allPayments = await paymentsRepo.paymentsByBooking(widget.booking.id).first;
      final totalPaid = allPayments.fold<double>(0, (s, p) => s + p.amount);
      final newRemaining = (currentTotal - totalPaid).clamp(0.0, currentTotal);

      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      if (cleanedPhone.isNotEmpty) {
        await _sendExtendedStayPaymentConfirmation(
          amount, 
          newRemaining, 
          cleanedPhone, 
          nights,
        );
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تسجيل دفع $nights ${nights == 1 ? 'ليلة' : 'ليالي'} إضافية - ${_currencyFmt.format(amount)}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('_processDailyPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء تسجيل الدفعة. يرجى المحاولة مرة أخرى'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  /// رسالة واتساب للدفع اليومي/الليالي الإضافية
  Future<void> _sendExtendedStayPaymentConfirmation(
    double amountPaidNow, 
    double remaining, 
    String cleanedPhone,
    int nightsPaid,
  ) async {
    if (cleanedPhone.isEmpty) return;
    
    final whatsappService = ref.read(whatsappServiceProvider);
    
    // Reuse the same builder but we can treat nightsPaid as addedNights
    // Note: The standard template handles extra nights generic text.
    // If we want specific text for manual extension, we might need to adjust template variables or logic.
    // For now, let's use the standard builder which is consistent.
    
    final message = await _buildMessage(
      amount: amountPaidNow,
      remaining: remaining,
      addedNights: nightsPaid,
      // Note: newCheckout is not passed here in original code but we can calculate/pass if needed.
      // For now we stick to existing behavior: just notify payment and extra nights.
    );
    
    try {
      await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال رسالة واتساب')),
        );
      }
    }
  }

  Future<void> _processPayment(
    PaymentMethod method,
    String amountText,
    String notes,
    String reference,
    String cardDigits,
    String bank,
  ) async {
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى إدخال مبلغ صحيح')));
      return;
    }

    final roomsRepo = ref.read(roomsRepoProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final bookingsRepo = ref.read(bookingsRepoProvider);

    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final roomRate = room?.price ?? 0;
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final plannedCheckout = _resolvePlannedCheckout();
    final actualCheckout = widget.booking.actualCheckout != null ? DateTime.tryParse(widget.booking.actualCheckout!) : null;
    final actualNights = Time.nightsWithCutoff(checkin, checkout: actualCheckout ?? plannedCheckout);
    final total = roomRate * actualNights;
    final existingPayments = await paymentsRepo.paymentsByBooking(widget.booking.id).first;
    final paidSoFar = existingPayments.fold<double>(0, (s, p) => s + p.amount);
    const double epsilon = 0.5;
    double remaining = ((total - paidSoFar).clamp(0.0, total)).toDouble();

    final cleanedPhone = _cleanAndFormatPhone(_phoneController.text);

    await bookingsRepo.update(widget.booking.id, guestPhone: cleanedPhone);
    if (mounted) {
      setState(() {
        _currentGuestPhone = cleanedPhone;
        if (_phoneController.text != cleanedPhone) {
          _phoneController.value = TextEditingValue(
            text: cleanedPhone,
            selection: TextSelection.collapsed(offset: cleanedPhone.length),
          );
        }
      });
    } else {
      _currentGuestPhone = cleanedPhone;
    }

    int autoExtensionNights = 0;
    DateTime? autoExtensionCheckout;
    double updatedTotal = total;
    double updatedRemainingBeforePayment = remaining;

    if (amount > remaining + epsilon) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Directionality(
          textDirection: ui.TextDirection.rtl,
          child: AlertDialog(
            title: const Text('المبلغ أكبر من المتبقي'),
            content: Text('المبلغ المتبقي هو ${_currencyFmt.format(remaining)} ريال، بينما أدخلت ${_currencyFmt.format(amount)} ريال.\nهل تريد المتابعة؟'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) {
        return;
      }

      if (roomRate <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يمكن تمديد الإقامة لأن سعر الليلة غير محدد')));
        return;
      }
      final extra = amount - remaining;
      autoExtensionNights = (extra / roomRate).ceil();
      if (autoExtensionNights < 1) {
        autoExtensionNights = 1;
      }

      updatedTotal += autoExtensionNights * roomRate;
      updatedRemainingBeforePayment += autoExtensionNights * roomRate;

      final baseCheckout = (_plannedCheckoutOverride ?? plannedCheckout) ?? DateTime.now().add(const Duration(days: 1));
      autoExtensionCheckout = baseCheckout.add(Duration(days: autoExtensionNights));
      final newExpectedNights = _resolveExpectedNights(checkin, plannedCheckout) + autoExtensionNights;
      final currentNotes = _bookingNotesOverride ?? widget.booking.notes;
      final extensionNote = 'تمديد تلقائي $autoExtensionNights ${autoExtensionNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}';
      final updatedNotes = (currentNotes != null && currentNotes.isNotEmpty)
          ? '$currentNotes\n$extensionNote'
          : extensionNote;
      final shouldPersistCheckout = widget.booking.checkoutDate != null;

      await bookingsRepo.update(
        widget.booking.id,
        checkoutDate: shouldPersistCheckout ? _formatDateTime(autoExtensionCheckout) : null,
        expectedNights: newExpectedNights,
        notes: updatedNotes,
      );

      if (mounted) {
        setState(() {
          _plannedCheckoutOverride = autoExtensionCheckout;
          _expectedNightsOverride = newExpectedNights;
          _bookingNotesOverride = updatedNotes;
        });
      } else {
        _plannedCheckoutOverride = autoExtensionCheckout;
        _expectedNightsOverride = newExpectedNights;
        _bookingNotesOverride = updatedNotes;
      }
    }

    if (amount > updatedRemainingBeforePayment + epsilon) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('المبلغ أكبر من المتبقي (${_currencyFmt.format(updatedRemainingBeforePayment)})')),
      );
      return;
    }

    String? paymentNotes = notes.isNotEmpty ? notes : null;
    if (autoExtensionNights > 0) {
      final extensionLabel = 'تمديد تلقائي $autoExtensionNights ${autoExtensionNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}';
      paymentNotes = paymentNotes == null ? extensionLabel : '$paymentNotes • $extensionLabel';
    }

    try {
      final paymentId = await paymentsRepo.create(
        bookingLocalId: widget.booking.id,
        roomNumber: widget.booking.roomNumber,
        amount: amount,
        paymentDate: Time.nowIso(),
        notes: paymentNotes,
        paymentMethod: _mapUiMethodToDb(method),
        revenueType: 'room',
      );
      
      if (paymentId <= 0) {
        throw Exception('فشل في إنشاء الدفعة');
      }
      
      markDataChanged();

      final newRemaining = ((updatedRemainingBeforePayment - amount).clamp(0.0, updatedTotal)).toDouble();

      if (mounted) {
        setState(() {
          _remainingAmount = newRemaining;
        });
      } else {
        _remainingAmount = newRemaining;
      }

      final receipt = Payment(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        bookingId: widget.booking.localUuid,
        amount: amount,
        method: method,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now(),
        notes: paymentNotes,
        referenceNumber: reference.isNotEmpty ? reference : null,
        cardLastFourDigits: cardDigits.isNotEmpty ? cardDigits : null,
        bankName: bank.isNotEmpty ? bank : null,
        receivedBy: 'admin',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _showReceiptDialog(receipt);

      if (cleanedPhone.isNotEmpty) {
        await _sendPaymentConfirmation(
          amount,
          newRemaining,
          cleanedPhone,
          addedNights: autoExtensionNights,
          newCheckout: autoExtensionCheckout,
        );
      }

      if (!mounted) {
        return;
      }

      final snackMessage = autoExtensionNights > 0
          ? 'تم تسجيل الدفعة وتم تمديد الإقامة $autoExtensionNights ${autoExtensionNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}'
          : 'تم تسجيل دفعة بقيمة ${_currencyFmt.format(amount)}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 20),
          content: Text(
            autoExtensionNights > 0
                ? '$snackMessage. المتبقي الجديد: ${_currencyFmt.format(newRemaining)}'
                : snackMessage,
          ),
          action: SnackBarAction(label: 'طباعة إيصال', onPressed: () => _generateReceipt(receipt)),
        ),
      );
    } catch (e) {
      debugPrint('_processPayment error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء تسجيل الدفعة. يرجى المحاولة مرة أخرى'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  void _showReceiptDialog(Payment payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تم تسجيل الدفعة بنجاح'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('المبلغ: ${_currencyFmt.format(payment.amount)}'),
            Text('طريقة الدفع: ${payment.method.displayName}'),
            Text('المتبقي: ${_currencyFmt.format(_remainingAmount)}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _generateReceipt(payment);
            },
            child: const Text('طباعة إيصال'),
          ),
        ],
      ),
    );
  }

  void _generateReceipt(Payment payment) async {
    final receipt = Receipt(
      receiptNumber: 'REC${DateTime.now().millisecondsSinceEpoch}',
      payment: payment,
      guestName: widget.booking.guestName,
      guestPhone: _currentGuestPhone,
      roomNumber: widget.booking.roomNumber,
      generatedAt: DateTime.now(),
    );
    await receipt.generatePDF();
  }

  void _generateInvoice(BookingPaymentSummary summary) async {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final plannedCheckout = _resolvePlannedCheckout();
    final actualCheckout = widget.booking.actualCheckout != null ? DateTime.tryParse(widget.booking.actualCheckout!) : null;
    final checkout = actualCheckout ?? plannedCheckout ?? checkin;
    final roomsRepo = ref.read(roomsRepoProvider);
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final invoice = Invoice(
      invoiceNumber: 'INV${DateTime.now().millisecondsSinceEpoch}',
      bookingId: widget.booking.localUuid,
      guestName: widget.booking.guestName,
      guestPhone: _currentGuestPhone,
      roomNumber: widget.booking.roomNumber,
      checkinDate: checkin,
      checkoutDate: checkout,
      nights: Time.nightsWithCutoff(checkin, checkout: checkout),
      roomRate: room?.price ?? 0,
      totalAmount: summary.totalAmount,
      payments: summary.payments,
      remainingAmount: summary.remainingAmount,
      generatedAt: DateTime.now(),
    );
    await invoice.generatePDF();
  }

  void _handleCheckout(BookingPaymentSummary summary) {
    if (summary.remainingAmount <= 0) {
      _showCheckoutConfirmation(summary);
    } else {
      _showCheckoutWithDebtDialog(summary);
    }
  }

  void _showCheckoutWithDebtDialog(BookingPaymentSummary summary) {
    final remainingText = _currencyFmt.format(summary.remainingAmount);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحويل المتبقي إلى دين'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('المبلغ المتبقي: $remainingText'),
            const SizedBox(height: 8),
            Text('سيتم إنشاء سجل دين باسم ${widget.booking.guestName} وربطه بالحجز الحالي.'),
            const SizedBox(height: 8),
            const Text('بعد التحويل سيتم تحرير الغرفة وتحديث حالة الحجز إلى مكتمل.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processCheckoutWithDebt(summary);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700),
            child: const Text('إنشاء دين وتحرير الغرفة'),
          ),
        ],
      ),
    );
  }

  void _showCheckoutConfirmation(BookingPaymentSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد المغادرة'),
        content: const Text(
          'هل تريد تسجيل مغادرة العميل وتحرير الغرفة؟\n\nسيتم تحديث حالة الحجز والغرفة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processCheckout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('تأكيد المغادرة'),
          ),
        ],
      ),
    );
  }

  void _processCheckout() async {
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final nowIso = Time.nowIso();
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final nowDate = DateTime.parse(nowIso);
    final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);
    await bookingsRepo.update(
      widget.booking.id,
      status: 'مكتمل',
      actualCheckout: nowIso,
      calculatedNights: actualNights,
    );
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    if (room != null) {
      await roomsRepo.update(room.id, status: 'شاغرة');
    }
    markDataChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل المغادرة بنجاح وتحرير الغرفة'), backgroundColor: Colors.green));
    Navigator.pop(context);
  }

  Future<void> _processCheckoutWithDebt(BookingPaymentSummary summary) async {
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final roomsRepo = ref.read(roomsRepoProvider);
    final debtsRepo = ref.read(debtsRepoProvider);
    final nowIso = Time.nowIso();
    final dateOnly = Time.nowDateString();
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final nowDate = DateTime.parse(nowIso);
    final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);

    try {
      final existingDebts = await debtsRepo.listByBookingLocalId(widget.booking.id);
      db.Debt? openDebt;
      for (final debt in existingDebts) {
        if (debt.isSettled == 0 && debt.remainingAmount > 0) {
          openDebt = debt;
          break;
        }
      }

      if (openDebt != null) {
        await debtsRepo.update(
          id: openDebt.id,
          totalAmount: summary.totalAmount,
          paidAmount: summary.paidAmount,
          checkoutDate: nowIso,
          dateRecorded: dateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          note: 'تحديث تلقائي من شاشة المدفوعات - غرفة ${widget.booking.roomNumber}',
        );
      } else {
        await debtsRepo.create(
          bookingLocalId: widget.booking.id,
          guestName: widget.booking.guestName,
          checkinDate: widget.booking.checkinDate,
          checkoutDate: nowIso,
          dateRecorded: dateOnly,
          debtReason: 'مغادرة مع مبلغ متبقي',
          totalAmount: summary.totalAmount,
          paidAmount: summary.paidAmount,
          paymentDate: dateOnly,
          isSettled: false,
          note: 'تم الإنشاء تلقائياً من شاشة المدفوعات (غرفة ${widget.booking.roomNumber})',
        );
      }

      await bookingsRepo.update(
        widget.booking.id,
        status: 'مكتمل',
        actualCheckout: nowIso,
        calculatedNights: actualNights,
      );

      final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
      if (room != null) {
        await roomsRepo.update(room.id, status: 'شاغرة');
      }
      markDataChanged();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحويل المبلغ المتبقي (${_currencyFmt.format(summary.remainingAmount)}) إلى سجل ديون وتحرير الغرفة'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تحويل الحجز إلى دين: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _sendAccountStatement(BookingPaymentSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال كشف حساب'),
        content: Text(
          'سيتم إرسال كشف حساب تفصيلي للعميل ${widget.booking.guestName} على رقم $_currentGuestPhone',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: إرسال كشف الحساب عبر WhatsApp أو SMS
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم إرسال كشف الحساب للعميل')),
              );
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  Future<void> _performSendAccountStatement(BookingPaymentSummary summary) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    
    // بناء كشف الحساب البسيط
    String statement = 'مارينا هوتل - كشف حساب\n';
    statement += 'العميل: ${widget.booking.guestName}\n';
    statement += 'الغرفة: ${widget.booking.roomNumber}\n';
    statement += 'تاريخ الوصول: ${widget.booking.checkinDate.split(' ')[0]}\n';
    if (widget.booking.checkoutDate != null) {
      statement += 'تاريخ المغادرة: ${widget.booking.checkoutDate!.split(' ')[0]}\n';
    }
    statement += '\nتفاصيل الحساب:\n';
    statement += 'المبلغ الإجمالي: ${_currencyFmt.format(summary.totalAmount)}\n';
    statement += 'المبلغ المدفوع: ${_currencyFmt.format(summary.paidAmount)}\n';
    statement += 'المبلغ المتبقي: ${_currencyFmt.format(summary.remainingAmount)}\n\n';
    
    if (summary.payments.isNotEmpty) {
      statement += 'سجل المدفوعات:\n';
      for (int i = 0; i < summary.payments.length; i++) {
        final payment = summary.payments[i];
        final paymentDate = DateFormat('dd/MM/yyyy', 'ar').format(payment.paymentDate);
        statement += '${i + 1}. ${_currencyFmt.format(payment.amount)} - ${payment.method.displayName} - $paymentDate\n';
      }
      statement += '\n';
    }
    
    if (summary.remainingAmount > 0) {
      statement += 'يرجى تسديد المبلغ المتبقي\n\n';
    } else {
      statement += 'تم سداد المبلغ بالكامل\n\n';
    }
    
    statement += 'شكراً لاختياركم فندق مارينا\n';
    statement += 'للاستفسار: 9677734587456';
    
    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final success = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: statement);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال كشف الحساب للعميل بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل في إرسال كشف الحساب'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال كشف الحساب: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sendPaymentReminder(BookingPaymentSummary summary) async {
    if (_currentGuestPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد رقم هاتف للعميل')),
      );
      return;
    }

    final whatsappService = ref.read(whatsappServiceProvider);
    
    // بناء رسالة تذكير بسيطة
    String reminder = 'عزيزي ${widget.booking.guestName}\n';
    reminder += 'تذكير بالمبلغ المتبقي\n';
    reminder += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    reminder += 'المبلغ الإجمالي: ${_currencyFmt.format(summary.totalAmount)}\n';
    reminder += 'المبلغ المدفوع: ${_currencyFmt.format(summary.paidAmount)}\n';
    reminder += 'المبلغ المتبقي: ${_currencyFmt.format(summary.remainingAmount)}\n\n';
    reminder += 'نرجو منكم تسديد المبلغ المتبقي في أقرب وقت ممكن\n\n';
    reminder += 'شكراً لتعاونكم معنا\n';
    reminder += 'للاستفسار: 9677734587456';
    
    try {
      final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
      final success = await whatsappService.sendMessage(phoneE164: cleanedPhone, message: reminder);
      
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال تذكير الدفع للعميل بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل في إرسال تذكير الدفع'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال التذكير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  /// نافذة حوار تمديد الإقامة
  void _showExtendStayDialog() {
    final roomsRepo = ref.watch(roomsRepoProvider);
    final nightsController = TextEditingController(text: '1');
    final notesController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => StreamBuilder<db.Room?>(
        stream: roomsRepo.watchByNumber(widget.booking.roomNumber),
        builder: (context, roomSnap) {
          final roomRate = roomSnap.data?.price ?? 0.0;
          
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_circle_outline, color: Colors.blue),
                const SizedBox(width: 8),
                const Text('تمديد الإقامة'),
              ],
            ),
            content: StatefulBuilder(
              builder: (context, setState) {
                final nights = int.tryParse(nightsController.text) ?? 1;
                final totalCost = nights * roomRate;
                
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text('سعر الليلة: ${_currencyFmt.format(roomRate)}'),
                          Text('عدد الليالي: $nights'),
                          Text(
                            'التكلفة الإجمالية: ${_currencyFmt.format(totalCost)}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nightsController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'عدد الليالي الإضافية',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        setState(() {}); // لتحديث التكلفة
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _processExtendStay(
                    int.tryParse(nightsController.text) ?? 1,
                    roomRate,
                    notesController.text,
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('تمديد وتسجيل دفعة'),
              ),
            ],
          );
        }
      ),
    );
  }

  /// معالجة تمديد الإقامة
  Future<void> _processExtendStay(int additionalNights, double roomRate, String notes) async {
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);

    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final plannedCheckout = _resolvePlannedCheckout();
    final baseCheckout = plannedCheckout ?? DateTime.now().add(const Duration(days: 1));
    final newCheckout = baseCheckout.add(Duration(days: additionalNights));
    final currentExpectedNights = _resolveExpectedNights(checkin, plannedCheckout);
    final newExpectedNights = currentExpectedNights + additionalNights;

    final currentNotes = _bookingNotesOverride ?? widget.booking.notes;
    final extensionNote = 'تمديد: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}';
    final updatedNotes = currentNotes != null && currentNotes.isNotEmpty
        ? '$currentNotes\n$extensionNote'
        : extensionNote;
    final shouldPersistCheckout = widget.booking.checkoutDate != null;

    await bookingsRepo.update(
      widget.booking.id,
      checkoutDate: shouldPersistCheckout ? _formatDateTime(newCheckout) : null,
      expectedNights: newExpectedNights,
      notes: updatedNotes,
    );

    if (mounted) {
      setState(() {
        _plannedCheckoutOverride = newCheckout;
        _expectedNightsOverride = newExpectedNights;
        _bookingNotesOverride = updatedNotes;
      });
    } else {
      _plannedCheckoutOverride = newCheckout;
      _expectedNightsOverride = newExpectedNights;
      _bookingNotesOverride = updatedNotes;
    }

    final amount = additionalNights * roomRate;
    await paymentsRepo.create(
      bookingLocalId: widget.booking.id,
      roomNumber: widget.booking.roomNumber,
      amount: amount,
      paymentDate: Time.nowIso(),
      notes: notes.isEmpty
          ? 'تمديد $additionalNights ${additionalNights == 1 ? 'ليلة إضافية' : 'ليالي إضافية'}'
          : notes,
      paymentMethod: 'نقدي',
      revenueType: 'room',
    );

    final cleanedPhone = _cleanAndFormatPhone(_currentGuestPhone);
    if (cleanedPhone.isNotEmpty) {
      await _sendExtensionConfirmation(additionalNights, amount, newCheckout, cleanedPhone);
    }

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تمديد الإقامة $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'} وتسجيل الدفعة'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// رسالة تأكيد تمديد الإقامة
  Future<void> _sendExtensionConfirmation(
    int additionalNights, 
    double amount, 
    DateTime newCheckout,
    String cleanedPhone,
  ) async {
    final whatsappService = ref.read(whatsappServiceProvider);
    
    String formatAmount(double amount) {
      if (amount == amount.toInt()) {
        return '${amount.toInt()}';
      } else {
        return _currencyFmt.format(amount);
      }
    }
    
    String message = 'عزيزي ${widget.booking.guestName}، تم تمديد إقامتكم\n';
    message += 'رقم الغرفة: ${widget.booking.roomNumber}\n';
    message += 'ليالي إضافية: $additionalNights ${additionalNights == 1 ? 'ليلة' : 'ليالي'}\n';
    message += 'المبلغ المدفوع: ${formatAmount(amount)} ريال\n';
    message += 'تاريخ المغادرة الجديد: ${newCheckout.day}/${newCheckout.month}/${newCheckout.year}\n';
    message += 'شكراً لاختيارك فندق مارينا\n';
    message += 'للاستفسار: 9677734587456';
    
    try {
      await whatsappService.sendMessage(phoneE164: cleanedPhone, message: message);
    } catch (_) {
      // تجاهل الأخطاء، الدفعة مسجلة بنجاح
    }
  }

  String _formatDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s';
  }
}