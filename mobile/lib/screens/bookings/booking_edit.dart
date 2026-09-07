// ignore_for_file: use_build_context_synchronously
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../mixins/sync_on_exit_mixin.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/custom_list_providers.dart';
import '../../providers/repository_providers.dart';
import '../../providers/room_payment_status_provider.dart';
import '../../providers/service_providers.dart';
import '../../services/local_db.dart';
import '../../services/screen_sync_controller.dart';
import '../../utils/debug_log.dart';
import '../../utils/english_digits_input_formatter.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';

class BookingEditScreen extends ConsumerStatefulWidget {
  const BookingEditScreen({super.key, this.existing, this.initialRoomNumber});
  final Booking? existing;
  final String? initialRoomNumber;
  @override
  ConsumerState<BookingEditScreen> createState() => _BookingEditScreenState();
}

class _BookingEditScreenState extends ConsumerState<BookingEditScreen>
    with SyncOnExitMixin {
  @override
  String get screenId => 'booking_edit';

  @override
  Duration get debounceDelay => const Duration(seconds: 15);

  final _formKey = GlobalKey<FormState>();
  final _guestName = TextEditingController();
  final _guestPhone = TextEditingController();
  final _guestNationality = TextEditingController(text: 'يمني');
  final _guestAddress = TextEditingController();
  final _guestIdNumber = TextEditingController();
  final _guestIdIssueDate = TextEditingController();
  final _guestIdIssuePlace = TextEditingController();
  final _roomNumber = TextEditingController();
  final _checkin = TextEditingController();
  final _checkout = TextEditingController();
  final _expectedNights = TextEditingController(text: '1');
  final _notes = TextEditingController();

  String _status = 'محجوزة';
  String _idType = 'بطاقة شخصية';
  bool _roomInitialized = false;
  bool _isSaving = false;

  // متغيرات الدفع المتقدم
  bool _hasAdvancePayment = false;
  final _advancePayment = TextEditingController();
  String _paymentMethod = 'نقدي';
  final _paymentNotes = TextEditingController();

  /// أنواع الهوية من القائمة الديناميكية
  List<String> get _idTypes {
    final asyncTypes = ref.watch(customListNamesProvider(kListKeyIdType));
    final types = asyncTypes.valueOrNull ?? kDefaultIdTypes;
    // التأكد من أن القيمة المحددة موجودة في القائمة
    if (_idType.isNotEmpty && !types.contains(_idType)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(
            () => _idType = types.isNotEmpty ? types.first : 'بطاقة شخصية',
          );
        }
      });
    }
    return types;
  }

  /// طرق الدفع من القائمة الديناميكية
  List<String> get _paymentMethods {
    final asyncTypes = ref.watch(
      customListNamesProvider(kListKeyPaymentMethod),
    );
    final methods = asyncTypes.valueOrNull ?? kDefaultPaymentMethods;
    // التأكد من أن القيمة المحددة موجودة في القائمة
    if (_paymentMethod.isNotEmpty && !methods.contains(_paymentMethod)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(
            () => _paymentMethod = methods.isNotEmpty ? methods.first : 'نقدي',
          );
        }
      });
    }
    return methods;
  }

  static const _statusOptions = ['محجوزة', 'مؤقت', 'شاغرة', 'مكتمل', 'ملغي'];

  @override
  void initState() {
    super.initState();

    _guestName.addListener(markDataChanged);
    _guestPhone.addListener(markDataChanged);
    _guestNationality.addListener(markDataChanged);
    _guestAddress.addListener(markDataChanged);
    _guestIdNumber.addListener(markDataChanged);
    _guestIdIssueDate.addListener(markDataChanged);
    _guestIdIssuePlace.addListener(markDataChanged);
    _roomNumber.addListener(markDataChanged);
    _checkin.addListener(markDataChanged);
    _checkout.addListener(markDataChanged);
    _expectedNights.addListener(markDataChanged);
    _notes.addListener(markDataChanged);
    _advancePayment.addListener(markDataChanged);
    _paymentNotes.addListener(markDataChanged);

    final b = widget.existing;
    if (b != null) {
      _guestName.text = b.guestName;
      _guestPhone.text = b.guestPhone;
      _guestNationality.text = b.guestNationality.isEmpty
          ? 'يمني'
          : b.guestNationality;
      _guestAddress.text = b.guestAddress ?? '';
      _guestIdNumber.text = b.guestIdNumber;
      _guestIdIssueDate.text = b.guestIdIssueDate ?? '';
      _guestIdIssuePlace.text = b.guestIdIssuePlace ?? '';
      _roomNumber.text = b.roomNumber;
      _checkin.text = b.checkinDate;
      _checkout.text = b.checkoutDate ?? '';
      _expectedNights.text = b.expectedNights.toString();
      _notes.text = b.notes ?? '';
      _status = b.status;
      _idType = b.guestIdType;
      _roomInitialized = true;
    } else {
      if (widget.initialRoomNumber != null &&
          widget.initialRoomNumber!.isNotEmpty) {
        _roomNumber.text = widget.initialRoomNumber!;
        _roomInitialized = true;
      }
      _checkin.text = _formatDateTime(DateTime.now());
      final hour = DateTime.now().hour;
      if (hour >= 9 && hour < 14) {
        _status = 'مؤقت';
      }
    }
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _recalculateExpectedNights(),
    );
  }

  @override
  void dispose() {
    _guestName.removeListener(markDataChanged);
    _guestPhone.removeListener(markDataChanged);
    _guestNationality.removeListener(markDataChanged);
    _guestAddress.removeListener(markDataChanged);
    _guestIdNumber.removeListener(markDataChanged);
    _guestIdIssueDate.removeListener(markDataChanged);
    _guestIdIssuePlace.removeListener(markDataChanged);
    _roomNumber.removeListener(markDataChanged);
    _checkin.removeListener(markDataChanged);
    _checkout.removeListener(markDataChanged);
    _expectedNights.removeListener(markDataChanged);
    _notes.removeListener(markDataChanged);
    _advancePayment.removeListener(markDataChanged);
    _paymentNotes.removeListener(markDataChanged);

    _guestName.dispose();
    _guestPhone.dispose();
    _guestNationality.dispose();
    _guestAddress.dispose();
    _guestIdNumber.dispose();
    _guestIdIssueDate.dispose();
    _guestIdIssuePlace.dispose();
    _roomNumber.dispose();
    _checkin.dispose();
    _checkout.dispose();
    _expectedNights.dispose();
    _notes.dispose();
    _advancePayment.dispose();
    _paymentNotes.dispose();
    super.dispose();
  }

  Future<void> _pickContact() async {
    final status = await Permission.contacts.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('يرجى منح صلاحية الوصول لجهات الاتصال')),
        );
      }
      return;
    }

    final contact = await FlutterContacts.openExternalPick();
    if (contact == null || !mounted) {
      return;
    }

    final fullContact = await FlutterContacts.getContact(contact.id);
    if (!mounted) {
      return;
    }

    if (fullContact != null && fullContact.phones.isNotEmpty) {
      final rawPhone = fullContact.phones.first.number;
      final normalizedPhone = _normalizePhoneForWhatsApp(rawPhone);
      _guestPhone.text = normalizedPhone;
      if (_guestName.text.isEmpty) {
        _guestName.text = fullContact.displayName;
      }
      markDataChanged();
    }
  }

  String _normalizePhoneForWhatsApp(String value) {
    var phone = value.replaceAll(RegExp('[^0-9+]'), '');
    if (phone.startsWith('+')) {
      phone = phone.substring(1);
    }
    if (phone.startsWith('00')) {
      phone = phone.substring(2);
    }
    if (phone.startsWith('0') && phone.length == 10) {
      phone = '967${phone.substring(1)}';
    }
    if (!phone.startsWith('967') && phone.length == 9) {
      phone = '967$phone';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(bookingsRepoProvider);
    final roomsAsync = ref.watch(roomsListProvider);
    return PopScope(
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.existing == null ? 'إضافة حجز' : 'تعديل حجز'),
          actions: [
            StreamBuilder<SyncStatus>(
              stream: syncStatusStream,
              builder: (context, snapshot) {
                final status = snapshot.data ?? SyncStatus.idle;
                return _buildSyncIndicator(status);
              },
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _buildSectionTitle('بيانات النزيل'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _guestName,
                        decoration: const InputDecoration(
                          labelText: 'اسم النزيل *',
                        ),
                        validator: _req,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _guestPhone,
                        decoration: InputDecoration(
                          labelText: 'رقم الهاتف',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.contacts),
                            tooltip: 'اختيار من جهات الاتصال',
                            onPressed: _pickContact,
                          ),
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: const [englishIntegerInputFormatter],
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _idTypes.contains(_idType)
                            ? _idType
                            : null,
                        items: _idTypes
                            .map(
                              (t) => DropdownMenuItem(value: t, child: Text(t)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _idType = value ?? _idType),
                        decoration: const InputDecoration(
                          labelText: 'نوع الهوية',
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _guestIdNumber,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهوية *',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: const [englishIntegerInputFormatter],
                        validator: _req,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _guestIdIssueDate,
                              readOnly: true,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'تاريخ إصدار الهوية',
                                suffixIcon: Icon(Icons.calendar_today),
                              ),
                              onTap: () =>
                                  _pickDate(_guestIdIssueDate, onlyDate: true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _guestIdIssuePlace,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'جهة الإصدار',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _guestNationality,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.normal,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'الجنسية *',
                        ),
                        validator: _req,
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _guestAddress,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(labelText: 'العنوان'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('تفاصيل الحجز'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    children: [
                      _buildRoomSelector(roomsAsync),
                      const SizedBox(height: 6),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _checkin,
                        readOnly: true,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الوصول *',
                          helperText: 'التنسيق: YYYY-MM-DD HH:MM:SS',
                          suffixIcon: Icon(Icons.event_available),
                        ),
                        validator: _req,
                        onTap: () => _pickDate(_checkin),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _checkout,
                        readOnly: true,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'تاريخ المغادرة المخطط',
                          helperText: 'التنسيق: YYYY-MM-DD HH:MM:SS',
                          suffixIcon: Icon(Icons.event_busy),
                        ),
                        onChanged: (_) => _recalculateExpectedNights(),
                        onTap: () => _pickDate(_checkout),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        items: _statusOptions
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _status = value ?? _status),
                        decoration: const InputDecoration(
                          labelText: 'حالة الحجز',
                        ),
                      ),
                      TextFormField(
                        controller: _expectedNights,
                        readOnly: true,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'عدد الليالي',
                        ),
                      ),
                      if (widget.existing?.actualCheckout != null) ...[
                        const SizedBox(height: 6),
                        TextFormField(
                          initialValue: widget.existing?.actualCheckout,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'تاريخ المغادرة الفعلي',
                            suffixIcon: Icon(Icons.lock_clock),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildSectionTitle('الدفع المقدم (اختياري)'),
              Card(
                color: _hasAdvancePayment
                    ? Colors.green.shade50
                    : Colors.grey.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        title: const Text('هل تم استلام دفعة مقدمة؟'),
                        subtitle: Text(
                          _hasAdvancePayment
                              ? 'سيتم تسجيل الدفعة مع الحجز مباشرة'
                              : 'يمكن تسجيل الدفعات لاحقاً من شاشة المدفوعات',
                        ),
                        value: _hasAdvancePayment,
                        onChanged: (value) =>
                            setState(() => _hasAdvancePayment = value ?? false),
                        activeColor: Colors.green,
                        dense: true,
                        visualDensity: const VisualDensity(
                          horizontal: -4,
                          vertical: -3,
                        ),
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_hasAdvancePayment) ...[
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _advancePayment,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [englishIntegerInputFormatter],
                          decoration: const InputDecoration(
                            labelText: 'مبلغ الدفعة المقدمة *',
                            helperText: 'أدخل المبلغ المستلم من النزيل',
                            // prefixText: 'ر.س ',
                          ),
                          validator: _hasAdvancePayment
                              ? (v) {
                                  if (v == null || v.trim().isEmpty) {
                                    return 'مطلوب عند تحديد دفعة مقدمة';
                                  }
                                  final amount = double.tryParse(v.trim());
                                  if (amount == null || amount <= 0) {
                                    return 'المبلغ يجب أن يكون أكبر من صفر';
                                  }
                                  return null;
                                }
                              : null,
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<String>(
                          initialValue: _paymentMethods.contains(_paymentMethod)
                              ? _paymentMethod
                              : null,
                          items: _paymentMethods
                              .map(
                                (method) => DropdownMenuItem(
                                  value: method,
                                  child: Text(method),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(
                            () => _paymentMethod = value ?? _paymentMethod,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'طريقة الدفع',
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: _paymentNotes,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات الدفعة',
                            helperText: 'مثال: عربون لثلاث ليالي',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              _buildSectionTitle('ملاحظات الحجز'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextFormField(
                    controller: _notes,
                    minLines: 1,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات إضافية',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: FilledButton.icon(
                  onPressed: _isSaving
                      ? null
                      : () async {
                          if (_formKey.currentState == null ||
                              !_formKey.currentState!.validate()) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'يرجى تعبئة اسم النزيل ورقم الهوية',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          final name = _guestName.text.trim();
                          final phone = _normalizePhone(_guestPhone.text);
                          final nationality =
                              _guestNationality.text.trim().isEmpty
                              ? 'غير معروف'
                              : _guestNationality.text.trim();
                          final address = _optionalText(_guestAddress.text);
                          final idNumber = _guestIdNumber.text.trim();
                          final idIssueDate = _optionalText(
                            _guestIdIssueDate.text,
                          );
                          final idIssuePlace = _optionalText(
                            _guestIdIssuePlace.text,
                          );
                          final roomNumber = _roomNumber.text.trim();
                          final checkin = _checkin.text.trim();
                          final checkout = _optionalText(_checkout.text);
                          final expectedNights =
                              int.tryParse(_expectedNights.text.trim()) ?? 1;
                          // ✅ فحص تسلسل التواريخ
                          final checkinDt = _parseDateTime(checkin);
                          final checkoutDt = checkout != null
                              ? _parseDateTime(checkout)
                              : null;
                          if (checkinDt != null &&
                              checkoutDt != null &&
                              checkoutDt.isBefore(checkinDt)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تاريخ المغادرة يجب أن يكون بعد تاريخ الوصول',
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }
                          final calculatedNights = checkinDt == null
                              ? expectedNights
                              : (checkoutDt == null && widget.existing == null)
                              ? 1
                              : Time.nightsWithCutoff(
                                  checkinDt,
                                  checkout: checkoutDt,
                                );
                          final notes = _optionalText(_notes.text);
                          // email removed - unused

                          // فحص القائمة السوداء (مطابقة أول 3 أسماء)
                          final blacklist = ref.read(blacklistRepoProvider);
                          final blacklistedMatch = await blacklist
                              .findBlacklistMatch(name);
                          if (blacklistedMatch != null && mounted) {
                            final e = blacklistedMatch;
                            final snackBar = SnackBar(
                              duration: const Duration(seconds: 30),
                              backgroundColor: Colors.red.shade900,
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(
                                        Icons.gavel,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'تحذير أمني — اسم في القائمة السوداء',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    e.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (e.nationality != null &&
                                      e.nationality!.isNotEmpty)
                                    Text(
                                      'الجنسية: ${e.nationality}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (e.nationalId != null &&
                                      e.nationalId!.isNotEmpty)
                                    Text(
                                      'الهوية: ${e.nationalId}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (e.phone != null && e.phone!.isNotEmpty)
                                    Text(
                                      'الهاتف: ${e.phone}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                  if (e.reason != null && e.reason!.isNotEmpty)
                                    Text(
                                      'السبب: ${e.reason}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                              action: SnackBarAction(
                                label: 'متابعة الحجز',
                                textColor: Colors.yellow,
                                onPressed: () {
                                  /* يكمل التنفيذ تلقائياً */
                                },
                              ),
                            );
                            ScaffoldMessenger.of(context).clearSnackBars();
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(snackBar);
                            // لا نوقف الحجز — نعرض التحذير فقط
                          }

                          try {
                            setState(() => _isSaving = true);
                            int? newBookingId;
                            if (widget.existing == null) {
                              newBookingId = await repo.create(
                                roomNumber: roomNumber,
                                guestName: name,
                                guestPhone: phone,
                                guestIdType: _idType,
                                guestIdNumber: idNumber,
                                guestIdIssueDate: idIssueDate,
                                guestIdIssuePlace: idIssuePlace,
                                guestNationality: nationality,
                                guestAddress: address,
                                checkinDate: checkin,
                                checkoutDate: checkout,
                                status: _status,
                                notes: notes,
                                expectedNights: expectedNights,
                                calculatedNights: calculatedNights,
                              );
                            } else {
                              newBookingId = widget.existing!.id;

                              // ✅ عند تغيير الحالة إلى "مكتمل"، نسجّل المغادرة الفعلية تلقائياً
                              // ونُحرّر الغرفة — تماماً كما يفعل _completeCheckout في booking_checkout_screen
                              final wasNotCompleted =
                                  widget.existing!.status != 'مكتمل';
                              final isNowCompleted = _status == 'مكتمل';
                              String? actualCheckoutValue;
                              int? checkoutCalculatedNights;

                              if (isNowCompleted && wasNotCompleted) {
                                final nowIso = Time.nowIso();
                                actualCheckoutValue = nowIso;
                                final checkinDate =
                                    DateTime.tryParse(checkin) ??
                                    DateTime.now();
                                final nowDate = DateTime.parse(nowIso);
                                checkoutCalculatedNights =
                                    Time.nightsWithCutoff(
                                      checkinDate,
                                      checkout: nowDate,
                                    );
                              }

                              await repo.update(
                                widget.existing!.id,
                                roomNumber: roomNumber,
                                guestName: name,
                                guestPhone: phone,
                                guestIdType: _idType,
                                guestIdNumber: idNumber,
                                guestIdIssueDate: idIssueDate,
                                guestIdIssuePlace: idIssuePlace,
                                guestNationality: nationality,
                                guestAddress: address,
                                checkinDate: checkin,
                                checkoutDate: checkout,
                                actualCheckout: actualCheckoutValue,
                                status: _status,
                                notes: notes,
                                expectedNights: expectedNights,
                                calculatedNights:
                                    checkoutCalculatedNights ??
                                    calculatedNights,
                              );

                              // ✅ تحديث حالة الغرف بعد تسجيل المغادرة
                              if (isNowCompleted && wasNotCompleted) {
                                await _refreshRoomOccupancy(ref);
                              }
                            }

                            // ✅ الحفظ نجح — نلغي حالة "تغييرات غير مزامنة"
                            // حتى لا يمنع PopScope الخروج
                            markSaved();

                            // ✅ رفع فوري لإنشاء/تحديث الحجز إلى Appwrite Cloud.
                            // قبل الإصلاح: كان الرفع يحدث فقط عبر syncNow() في نهاية الكتلة،
                            // وهي مزامنة كاملة (push + pull) أثقل — pushLocalChanges أسرع
                            // لأنها push-only بدون pull.
                            unawaited(
                              ref
                                  .read(appwriteSyncManagerProvider)
                                  .pushLocalChanges(),
                            );

                            // ✅ حفظ الدفعة المقدمة إذا تم تحديدها
                            if (_hasAdvancePayment) {
                              final advanceAmount = double.tryParse(
                                _advancePayment.text.trim(),
                              );
                              if (advanceAmount != null && advanceAmount > 0) {
                                try {
                                  final paymentsRepo = ref.read(
                                    paymentsRepoProvider,
                                  );
                                  await paymentsRepo.create(
                                    bookingLocalId: newBookingId,
                                    roomNumber: roomNumber,
                                    amount: advanceAmount,
                                    paymentDate: Time.nowIso(),
                                    notes: _paymentNotes.text.trim().isEmpty
                                        ? null
                                        : _paymentNotes.text.trim(),
                                    paymentMethod: _paymentMethod,
                                    revenueType: 'deposit',
                                  );
                                } catch (e) {
                                  dlog(
                                    () => '⚠️ خطأ في حفظ الدفعة المقدمة: $e',
                                  );
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'تم حفظ الحجز لكن فشل حفظ الدفعة المقدمة: $e',
                                        ),
                                        backgroundColor: Colors.orange,
                                      ),
                                    );
                                  }
                                }
                              }
                            }

                            await _refreshRoomOccupancy(ref);
                            ref.invalidate(roomsListProvider);
                            ref.invalidate(bookingsListProvider);
                            ref.invalidate(roomsWithPaymentStatusProvider);

                            await syncNow();
                            if (mounted) {
                              Navigator.pop(context);
                            }
                          } on StateError catch (e) {
                            // خطأ منطقي (مثل: حجز مزدوج لنفس الغرفة)
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.message),
                                  backgroundColor: Colors.red.shade900,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                          } catch (e) {
                            // أي خطأ آخر (قاعدة بيانات، شبكة، إلخ)
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('فشل حفظ الحجز: $e'),
                                  backgroundColor: Colors.red.shade900,
                                  duration: const Duration(seconds: 3),
                                ),
                              );
                            }
                            dlog(() => '❌ خطأ في حفظ الحجز: $e');
                          } finally {
                            if (mounted) {
                              setState(() => _isSaving = false);
                            }
                          }
                        },
                  icon: const Icon(Icons.save),
                  label: const Text('حفظ الحجز'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncIndicator(SyncStatus status) {
    switch (status) {
      case SyncStatus.pending:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(
            Icons.cloud_upload_outlined,
            color: Colors.orange,
            size: 20,
          ),
        );
      case SyncStatus.syncing:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.blue,
            ),
          ),
        );
      case SyncStatus.synced:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.cloud_done, color: Colors.green, size: 20),
        );
      case SyncStatus.queued:
        return const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.cloud_off, color: Colors.grey, size: 20),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _pickDate(
    TextEditingController controller, {
    bool onlyDate = false,
  }) async {
    final initial = _parseDateTime(controller.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) {
      return;
    }
    if (onlyDate) {
      controller.text = _formatDateTime(
        DateTime(date.year, date.month, date.day),
      ).substring(0, 10);
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) {
      return;
    }
    final selected = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    setState(() {
      controller.text = _formatDateTime(selected);
    });
    if (controller == _checkout || controller == _checkin) {
      _recalculateExpectedNights();
    }
  }

  void _recalculateExpectedNights() {
    final checkinDt = _parseDateTime(_checkin.text.trim());
    if (checkinDt == null) {
      return;
    }
    final checkoutDt = _parseDateTime(_checkout.text.trim());

    // استخدام الوقت الحالي كمرجع للمغادرة إذا لم يتم تحديد موعد خروج مخطط له
    // لضمان تطبيق قاعدة الساعة 14:00 بشكل ديناميكي
    final effectiveCheckout = checkoutDt ?? DateTime.now();

    final nights = Time.nightsWithCutoff(
      checkinDt,
      checkout: effectiveCheckout,
    );

    setState(() {
      _expectedNights.text = nights.toString();
    });
  }

  Widget _buildRoomSelector(AsyncValue<List<Room>> roomsAsync) {
    final roomTextStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.bold,
      color: Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black87,
    );
    return roomsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(),
      ),
      error: (err, stack) => TextFormField(
        controller: _roomNumber,
        readOnly: true,
        style: roomTextStyle,
        decoration: const InputDecoration(
          labelText: 'رقم الغرفة *',
          helperText: 'تعذر تحميل قائمة الغرف، أدخل الرقم يدوياً',
        ),
        validator: _req,
      ),
      data: (rooms) {
        final availableRooms =
            rooms
                .where((room) => StatusUtils.isRoomAvailable(room.status))
                .toList()
              ..sort((a, b) => a.roomNumber.compareTo(b.roomNumber));

        final currentValue = _roomNumber.text.trim();
        if (!_roomInitialized &&
            widget.existing == null &&
            availableRooms.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _roomNumber.text = availableRooms.first.roomNumber;
                _roomInitialized = true;
              });
            }
          });
        } else if (!_roomInitialized && widget.existing != null) {
          _roomInitialized = true;
        }

        final items = <DropdownMenuItem<String>>[];
        if (currentValue.isNotEmpty &&
            !availableRooms.any((room) => room.roomNumber == currentValue)) {
          items.add(
            DropdownMenuItem(
              value: currentValue,
              child: Text('$currentValue (الحالي)', style: roomTextStyle),
            ),
          );
        }
        items.addAll(
          availableRooms.map(
            (room) => DropdownMenuItem(
              value: room.roomNumber,
              child: Text(
                '${room.roomNumber} • ${room.type}',
                style: roomTextStyle,
              ),
            ),
          ),
        );

        if (items.isEmpty) {
          return TextFormField(
            controller: _roomNumber,
            readOnly: widget.existing == null,
            style: roomTextStyle,
            decoration: const InputDecoration(
              labelText: 'رقم الغرفة *',
              helperText: 'لا توجد غرف شاغرة متاحة حالياً',
            ),
            validator: _req,
          );
        }

        return DropdownButtonFormField<String>(
          initialValue: currentValue.isNotEmpty ? currentValue : null,
          items: items,
          style: roomTextStyle,
          onChanged: (value) {
            setState(() {
              _roomNumber.text = value ?? '';
            });
          },
          decoration: const InputDecoration(labelText: 'رقم الغرفة *'),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'مطلوب' : null,
        );
      },
    );
  }

  Future<void> _refreshRoomOccupancy(WidgetRef ref) async {
    try {
      // استخدام المستودع الموحد لتحديث حالة الغرف بناءً على الحجوزات النشطة
      final roomsRepo = ref.read(roomsRepoProvider);
      await roomsRepo.refreshAllRoomOccupancy();

      // إشعار أنظمة المزامنة والنسخ الاحتياطي بالتغييرات (method واحد موحد)
      await ref
          .read(centralSyncCoordinatorProvider)
          .notifyTableChange(table: 'rooms', operation: 'batch_update_status');
    } catch (e) {
      dlog(() => 'Error refreshing room occupancy: $e');
    }
  }

  DateTime? _parseDateTime(String value) {
    if (value.isEmpty) {
      return null;
    }
    final normalized = value.contains('T') ? value : value.replaceAll(' ', 'T');
    final withSeconds = normalized.length == 16 ? '$normalized:00' : normalized;
    try {
      return DateTime.parse(withSeconds);
    } catch (_) {
      return null;
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

  String _normalizePhone(String value) {
    final digitsOnly = value.replaceAll(RegExp('[^0-9]'), '');
    if (digitsOnly.isEmpty) {
      return value.trim();
    }
    var normalized = digitsOnly;
    if (normalized.startsWith('00') && normalized.length > 2) {
      normalized = normalized.substring(2);
    }
    if (normalized.startsWith('0') && normalized.length == 10) {
      normalized = normalized.substring(1);
    }
    if (normalized.startsWith('967')) {
      return normalized;
    }
    return '967$normalized';
  }

  String? _optionalText(String text) =>
      text.trim().isEmpty ? null : text.trim();
  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;

  // ignore: unused_element
  void _showDiscardDialog(BuildContext context) {
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تأكيد'),
          content: const Text('هل تريد المغادرة بدون حفظ التغييرات؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('لا'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await syncNow();
                if (mounted) {
                  Navigator.pop(context);
                }
              },
              child: const Text('نعم'),
            ),
          ],
        ),
      ),
    ));
  }
}
