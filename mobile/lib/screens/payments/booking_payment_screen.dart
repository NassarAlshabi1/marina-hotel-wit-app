import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../services/local_db.dart' as db;
import '../../models/payment_models.dart';
import '../../components/widgets/payment_widgets.dart';
import '../../services/providers.dart';
import '../../utils/time.dart';
import 'payment_history_screen.dart';

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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFmt = NumberFormat.decimalPattern('ar');
  PaymentMethod? _selectedMethod;

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final roomsRepo = ref.watch(roomsRepoProvider);
    final paymentsRepo = ref.watch(paymentsRepoProvider);

    return AppScaffold(
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
          final checkout = widget.booking.checkoutDate != null ? DateTime.tryParse(widget.booking.checkoutDate!) : null;
          final nights = Time.nightsWithCutoff(checkin, checkout: checkout);
          final totalAmount = nights * roomRate;
          return StreamBuilder<List<db.Payment>>(
            stream: paymentsRepo.paymentsByBooking(widget.booking.id),
            builder: (context, paySnap) {
              final dbPayments = paySnap.data ?? const <db.Payment>[];
              final paidAmount = dbPayments.fold<double>(0, (s, p) => s + p.amount);
              final remainingAmount = (totalAmount - paidAmount).clamp(0, totalAmount);
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
                  _buildPaymentSummaryCard(summary),
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
    );
  }

  Widget _buildPaymentSummaryCard(BookingPaymentSummary summary) {
    final progressPercentage = summary.paidPercentage / 100;
    
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
          // معلومات الحجز
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
                      'غرفة ${widget.booking.roomNumber} • ${widget.booking.guestPhone}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
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
          
          const SizedBox(height: 16),
          
          // شريط التقدم
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
          
          // ملخص المبالغ
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
            '${amount.toStringAsFixed(0)} ر.س',
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
          itemCount: PaymentMethod.values.length,
          itemBuilder: (context, index) {
            final method = PaymentMethod.values[index];
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
          Text('${_currencyFmt.format(amount)} ر.س', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildActionsTab(BookingPaymentSummary summary) {
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
          
          if (summary.isFullyPaid) ...[
            _buildActionCard(
              'تسجيل المغادرة',
              'تسجيل مغادرة العميل وتحرير الغرفة',
              Icons.logout,
              Colors.green,
              () => _showCheckoutConfirmation(summary),
            ),
          ],
          
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
                  if (widget.booking.checkoutDate != null)
                    _buildInfoRow('تاريخ المغادرة', widget.booking.checkoutDate!.split(' ')[0]),
                  _buildInfoRow('الحالة', widget.booking.status),
                  if (widget.booking.notes != null && widget.booking.notes!.isNotEmpty)
                    _buildInfoRow('ملاحظات', widget.booking.notes!),
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
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
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
        textDirection: TextDirection.rtl,
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
                      suffixText: 'ر.س',
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

    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final nights = Time.nightsWithCutoff(checkin, checkout: widget.booking.checkoutDate != null ? DateTime.tryParse(widget.booking.checkoutDate!) : null);
    final total = (room?.price ?? 0) * nights;
    final existingPayments = await paymentsRepo.paymentsByBooking(widget.booking.id).first;
    final paidSoFar = existingPayments.fold<double>(0, (s, p) => s + p.amount);
    final remaining = (total - paidSoFar).clamp(0, total);

    if (amount > remaining) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('المبلغ أكبر من المتبقي (${remaining.toStringAsFixed(2)} ر.س)')));
      return;
    }

    await paymentsRepo.create(
      bookingLocalId: widget.booking.id,
      roomNumber: widget.booking.roomNumber,
      amount: amount,
      paymentDate: Time.nowIso(),
      notes: notes.isEmpty ? null : notes,
      paymentMethod: _mapUiMethodToDb(method),
      revenueType: 'room',
    );

    Navigator.pop(context);

    final receipt = Payment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      bookingId: widget.booking.localUuid,
      amount: amount,
      method: method,
      status: PaymentStatus.completed,
      paymentDate: DateTime.now(),
      notes: notes.isNotEmpty ? notes : null,
      referenceNumber: reference.isNotEmpty ? reference : null,
      cardLastFourDigits: cardDigits.isNotEmpty ? cardDigits : null,
      bankName: bank.isNotEmpty ? bank : null,
      receivedBy: 'admin',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    _showReceiptDialog(receipt);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تسجيل دفعة بقيمة ${amount.toStringAsFixed(2)} ر.س'),
        action: SnackBarAction(label: 'طباعة إيصال', onPressed: () => _generateReceipt(receipt)),
      ),
    );
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
            Text('المبلغ: ${payment.amount.toStringAsFixed(2)} ر.س'),
            Text('طريقة الدفع: ${payment.method.displayName}'),
            Text('المتبقي: ${_remainingAmount.toStringAsFixed(2)} ر.س'),
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
      guestPhone: widget.booking.guestPhone,
      roomNumber: widget.booking.roomNumber,
      generatedAt: DateTime.now(),
    );
    await receipt.generatePDF();
  }

  void _generateInvoice(BookingPaymentSummary summary) async {
    final checkin = DateTime.tryParse(widget.booking.checkinDate) ?? DateTime.now();
    final checkout = widget.booking.checkoutDate != null ? DateTime.tryParse(widget.booking.checkoutDate!)! : DateTime.now();
    final roomsRepo = ref.read(roomsRepoProvider);
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    final invoice = Invoice(
      invoiceNumber: 'INV${DateTime.now().millisecondsSinceEpoch}',
      bookingId: widget.booking.localUuid,
      guestName: widget.booking.guestName,
      guestPhone: widget.booking.guestPhone,
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
    await bookingsRepo.update(widget.booking.id, status: 'مكتمل', checkoutDate: Time.nowIso());
    final room = await roomsRepo.watchByNumber(widget.booking.roomNumber).first;
    if (room != null) {
      await roomsRepo.update(room.id, status: 'شاغرة');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل المغادرة بنجاح وتحرير الغرفة'), backgroundColor: Colors.green));
    Navigator.pop(context);
  }

  void _sendAccountStatement(BookingPaymentSummary summary) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال كشف حساب'),
        content: Text(
          'سيتم إرسال كشف حساب تفصيلي للعميل ${widget.booking.guestName} على رقم ${widget.booking.guestPhone}',
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
}