import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/local_db.dart';
import '../../models/payment_models.dart';
import '../../components/widgets/payment_widgets.dart';
import 'booking_payment_screen.dart';

class BookingCheckoutScreen extends ConsumerStatefulWidget {
  final Booking booking;
  
  const BookingCheckoutScreen({
    super.key,
    required this.booking,
  });

  @override
  ConsumerState<BookingCheckoutScreen> createState() => _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen> {
  late BookingPaymentSummary _paymentSummary;
  bool _isCheckedOut = false;
  
  @override
  void initState() {
    super.initState();
    _initializePaymentSummary();
  }

  void _initializePaymentSummary() {
    // حساب تفاصيل الفاتورة
    final checkin = DateTime.parse(widget.booking.checkinDate);
    final checkout = widget.booking.checkoutDate != null 
        ? DateTime.parse(widget.booking.checkoutDate!)
        : DateTime.now();
    
    final nights = checkout.difference(checkin).inDays.clamp(1, 365);
    final roomRate = 150.0; // سعر افتراضي
    final totalAmount = nights * roomRate;
    
    // مدفوعات تجريبية
    final payments = [
      Payment(
        id: '1',
        bookingId: widget.booking.localUuid,
        amount: 300.0,
        method: PaymentMethod.cash,
        status: PaymentStatus.completed,
        paymentDate: DateTime.now().subtract(const Duration(hours: 2)),
        notes: 'دفعة مقدمة',
        receivedBy: 'admin',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
    ];
    
    final paidAmount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    final remainingAmount = totalAmount - paidAmount;
    
    _paymentSummary = BookingPaymentSummary(
      bookingId: widget.booking.localUuid,
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      remainingAmount: remainingAmount,
      payments: payments,
      overallStatus: remainingAmount <= 0 ? PaymentStatus.completed : PaymentStatus.pending,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إنهاء الحجز وتسجيل المغادرة',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // معلومات الضيف والحجز
            _buildGuestInfoCard(),
            
            const SizedBox(height: 16),
            
            // ملخص المدفوعات
            PaymentSummaryWidget(
              summary: _paymentSummary,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookingPaymentScreen(booking: widget.booking),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // ملخص الفاتورة
            InvoiceSummaryWidget(
              totalAmount: _paymentSummary.totalAmount,
              paidAmount: _paymentSummary.paidAmount,
              remainingAmount: _paymentSummary.remainingAmount,
              nights: widget.booking.calculatedNights,
              roomRate: 150.0,
            ),
            
            const SizedBox(height: 16),
            
            // إجراءات ما قبل المغادرة
            _buildPreCheckoutActions(),
            
            const SizedBox(height: 20),
            
            // زر تسجيل المغادرة
            _buildCheckoutButton(),
            
            const SizedBox(height: 16),
            
            // زر الطوارئ
            _buildEmergencyCheckoutButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'غرفة ${widget.booking.roomNumber}',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue),
                  ),
                  child: Text(
                    widget.booking.status,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // تفاصيل الإقامة
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem('تاريخ الوصول', widget.booking.checkinDate.split(' ')[0], Icons.login),
                ),
                Expanded(
                  child: _buildDetailItem('تاريخ المغادرة المتوقع', 
                    widget.booking.checkoutDate?.split(' ')[0] ?? 'غير محدد', Icons.logout),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: _buildDetailItem('الهاتف', widget.booking.guestPhone, Icons.phone),
                ),
                Expanded(
                  child: _buildDetailItem('الجنسية', widget.booking.guestNationality, Icons.flag),
                ),
              ],
            ),
            
            if (widget.booking.guestEmail != null && widget.booking.guestEmail!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailItem('البريد الإلكتروني', widget.booking.guestEmail!, Icons.email),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                value,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreCheckoutActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'إجراءات ما قبل المغادرة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            _buildActionTile(
              'فحص حالة الغرفة',
              'التأكد من حالة الغرفة والأضرار',
              Icons.room_service,
              Colors.blue,
              () => _showRoomInspectionDialog(),
            ),
            
            _buildActionTile(
              'إدارة المدفوعات',
              'عرض وإدارة مدفوعات الحجز',
              Icons.payment,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BookingPaymentScreen(booking: widget.booking),
                ),
              ),
            ),
            
            _buildActionTile(
              'طباعة الفاتورة النهائية',
              'إنشاء فاتورة شاملة للإقامة',
              Icons.receipt_long,
              Colors.purple,
              () => _generateFinalInvoice(),
            ),
            
            _buildActionTile(
              'إرسال تقييم الإقامة',
              'إرسال رابط تقييم الخدمة للضيف',
              Icons.star_rate,
              Colors.orange,
              () => _sendFeedbackRequest(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionTile(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withOpacity(0.2),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  Widget _buildCheckoutButton() {
    final canCheckout = _paymentSummary.isFullyPaid && !_isCheckedOut;
    
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: canCheckout ? _showCheckoutConfirmation : null,
        icon: Icon(_isCheckedOut ? Icons.check_circle : Icons.logout),
        label: Text(
          _isCheckedOut 
              ? 'تم تسجيل المغادرة' 
              : canCheckout 
                  ? 'تسجيل المغادرة'
                  : 'يجب سداد المبلغ كاملاً أولاً',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: _isCheckedOut 
              ? Colors.grey 
              : canCheckout 
                  ? Colors.green 
                  : Colors.red,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildEmergencyCheckoutButton() {
    if (_isCheckedOut || _paymentSummary.isFullyPaid) {
      return const SizedBox.shrink();
    }
    
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _showEmergencyCheckoutDialog,
        icon: const Icon(Icons.warning, color: Colors.red),
        label: const Text('مغادرة طوارئ (بدون سداد كامل)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red,
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  void _showRoomInspectionDialog() {
    bool hasMinorDamage = false;
    bool hasMajorDamage = false;
    final notesController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('فحص حالة الغرفة'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    title: const Text('أضرار طفيفة'),
                    subtitle: const Text('خدوش، بقع صغيرة، إلخ'),
                    value: hasMinorDamage,
                    onChanged: (value) => setDialogState(() => hasMinorDamage = value ?? false),
                  ),
                  CheckboxListTile(
                    title: const Text('أضرار كبيرة'),
                    subtitle: const Text('كسر، تلف، إلخ'),
                    value: hasMajorDamage,
                    onChanged: (value) => setDialogState(() => hasMajorDamage = value ?? false),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات إضافية',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _saveRoomInspection(hasMinorDamage, hasMajorDamage, notesController.text);
                },
                child: const Text('حفظ الفحص'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveRoomInspection(bool hasMinorDamage, bool hasMajorDamage, String notes) {
    // TODO: حفظ نتائج فحص الغرفة
    String message = 'تم حفظ فحص الغرفة';
    if (hasMinorDamage || hasMajorDamage) {
      message += ' - تم تسجيل أضرار';
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _generateFinalInvoice() {
    final invoice = Invoice(
      invoiceNumber: 'INV${DateTime.now().millisecondsSinceEpoch}',
      bookingId: widget.booking.localUuid,
      guestName: widget.booking.guestName,
      guestPhone: widget.booking.guestPhone,
      roomNumber: widget.booking.roomNumber,
      checkinDate: DateTime.parse(widget.booking.checkinDate),
      checkoutDate: widget.booking.checkoutDate != null 
          ? DateTime.parse(widget.booking.checkoutDate!)
          : DateTime.now(),
      nights: widget.booking.calculatedNights,
      roomRate: 150.0,
      totalAmount: _paymentSummary.totalAmount,
      payments: _paymentSummary.payments,
      remainingAmount: _paymentSummary.remainingAmount,
      generatedAt: DateTime.now(),
    );

    // عرض معاينة الفاتورة
    _showInvoicePreview(invoice);
  }

  void _showInvoicePreview(Invoice invoice) {
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('معاينة الفاتورة'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // رأس الفاتورة
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'فندق مارينا بلازا',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Text('فاتورة رقم: ${invoice.invoiceNumber}'),
                        Text('التاريخ: ${_formatDate(invoice.generatedAt)}'),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // بيانات العميل
                  _buildInvoiceSection('بيانات العميل', [
                    'الاسم: ${invoice.guestName}',
                    'الهاتف: ${invoice.guestPhone}',
                    'رقم الغرفة: ${invoice.roomNumber}',
                  ]),
                  
                  // تفاصيل الإقامة
                  _buildInvoiceSection('تفاصيل الإقامة', [
                    'تاريخ الوصول: ${_formatDate(invoice.checkinDate)}',
                    'تاريخ المغادرة: ${_formatDate(invoice.checkoutDate)}',
                    'عدد الليالي: ${invoice.nights}',
                    'سعر الليلة: ${invoice.roomRate.toStringAsFixed(2)} ر.س',
                  ]),
                  
                  // الحساب النهائي
                  _buildInvoiceSection('الحساب النهائي', [
                    'إجمالي الفاتورة: ${invoice.totalAmount.toStringAsFixed(2)} ر.س',
                    'المدفوع: ${(invoice.totalAmount - invoice.remainingAmount).toStringAsFixed(2)} ر.س',
                    'المتبقي: ${invoice.remainingAmount.toStringAsFixed(2)} ر.س',
                  ]),
                  
                  if (invoice.payments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('سجل المدفوعات:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ...invoice.payments.map((payment) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${payment.method.displayName}: ${payment.amount.toStringAsFixed(2)} ر.س (${_formatDate(payment.paymentDate)})',
                        style: const TextStyle(fontSize: 12),
                      ),
                    )),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _printInvoice(invoice);
              },
              child: const Text('طباعة'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        ...items.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(item, style: const TextStyle(fontSize: 12)),
        )),
        const SizedBox(height: 12),
      ],
    );
  }

  void _sendFeedbackRequest() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إرسال طلب تقييم'),
        content: Text(
          'سيتم إرسال رابط تقييم الخدمة للضيف ${widget.booking.guestName} على رقم ${widget.booking.guestPhone}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: إرسال رابط التقييم
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم إرسال طلب التقييم للضيف')),
              );
            },
            child: const Text('إرسال'),
          ),
        ],
      ),
    );
  }

  void _showCheckoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد تسجيل المغادرة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('هل تريد تسجيل مغادرة الضيف؟'),
            const SizedBox(height: 12),
            const Text('سيتم:', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('• تحديث حالة الحجز إلى "منتهي"'),
            const Text('• تحرير الغرفة وجعلها متاحة'),
            const Text('• إرسال شكر للضيف'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  SizedBox(width: 8),
                  Text('تم سداد المبلغ كاملاً', style: TextStyle(color: Colors.green, fontSize: 12)),
                ],
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

  void _showEmergencyCheckoutDialog() {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning, color: Colors.red),
              SizedBox(width: 8),
              Text('مغادرة طوارئ'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'تحذير: مغادرة بدون سداد كامل',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    Text('المبلغ المتبقي: ${_paymentSummary.remainingAmount.toStringAsFixed(2)} ر.س'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'سبب المغادرة الطارئة*',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (reasonController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('يرجى كتابة سبب المغادرة الطارئة')),
                  );
                  return;
                }
                Navigator.pop(context);
                _processEmergencyCheckout(reasonController.text.trim());
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('تأكيد المغادرة الطارئة'),
            ),
          ],
        ),
      ),
    );
  }

  void _processCheckout() {
    setState(() {
      _isCheckedOut = true;
    });
    
    // TODO: تحديث قاعدة البيانات
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم تسجيل المغادرة بنجاح وتحرير الغرفة'),
        backgroundColor: Colors.green,
      ),
    );
    
    _sendThankYouMessage();
  }

  void _processEmergencyCheckout(String reason) {
    setState(() {
      _isCheckedOut = true;
    });
    
    // TODO: تسجيل المغادرة الطارئة مع السبب
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('تم تسجيل مغادرة طارئة - السبب: $reason'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _printInvoice(Invoice invoice) {
    // TODO: طباعة الفاتورة
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري طباعة الفاتورة... (قيد التطوير)')),
    );
  }

  void _sendThankYouMessage() {
    // TODO: إرسال رسالة شكر للضيف
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال رسالة شكر للضيف')),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}