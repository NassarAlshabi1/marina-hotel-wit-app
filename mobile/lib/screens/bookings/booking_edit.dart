import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/repository_providers.dart';
import '../../services/local_db.dart';
import '../../utils/status_utils.dart';
import '../../utils/time.dart';
import '../../mixins/sync_on_exit_mixin.dart';
import '../../services/screen_sync_controller.dart';
import '../../utils/theme.dart';

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

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late TextEditingController _guestCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _addressCtrl;
  late TextEditingController _nightlyCtrl;
  late TextEditingController _advanceCtrl;
  late TextEditingController _notesCtrl;
  late TextEditingController _nationalityCtrl;
  late TextEditingController _discountCtrl;
  late TextEditingController _idTypeCtrl;
  late TextEditingController _idNumberCtrl;
  late TextEditingController _idIssuePlaceCtrl;
  late TextEditingController _idIssueDateCtrl;

  String? _selectedRoom;
  String _selectedStatus = 'active';
  DateTime _checkinDate = DateTime.now();
  TimeOfDay _checkinTime = TimeOfDay.now();
  int _expectedNights = 1;

  List<Room> _rooms = [];
  List<Booking> _activeBookings = [];
  bool _loadingRooms = true;

  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _guestCtrl = TextEditingController(text: b?.guestName ?? '');
    _phoneCtrl = TextEditingController(text: b?.guestPhone ?? '');
    _addressCtrl = TextEditingController(text: b?.guestAddress ?? '');
    _nightlyCtrl =
        TextEditingController(text: b?.nightlyRate.toStringAsFixed(0) ?? '');
    _advanceCtrl =
        TextEditingController(text: b?.advancePayment.toStringAsFixed(0) ?? '');
    _notesCtrl = TextEditingController(text: b?.notes ?? '');
    _nationalityCtrl = TextEditingController(text: b?.guestNationality ?? '');
    _discountCtrl =
        TextEditingController(text: b?.discount?.toStringAsFixed(0) ?? '');
    _idTypeCtrl = TextEditingController(text: b?.guestIdType ?? '');
    _idNumberCtrl = TextEditingController(text: b?.guestIdNumber ?? '');
    _idIssuePlaceCtrl = TextEditingController(text: b?.guestIdIssuePlace ?? '');
    _idIssueDateCtrl = TextEditingController(text: b?.guestIdIssueDate ?? '');

    if (b != null) {
      _selectedRoom = b.roomNumber;
      _selectedStatus = b.status;
      _checkinDate = b.checkinDate;
      _checkinTime = TimeOfDay(hour: b.checkinDate.hour, minute: b.checkinDate.minute);
      _expectedNights = b.expectedNights ?? 1;
    } else if (widget.initialRoomNumber != null) {
      _selectedRoom = widget.initialRoomNumber;
    }

    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final repo = ref.read(roomsRepoProvider);
    final bookingsRepo = ref.read(bookingsRepoProvider);
    final rooms = await repo.getAll();
    final activeBookings =
        await bookingsRepo.getAllActive(includeReserved: true);
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _activeBookings = activeBookings;
        _loadingRooms = false;
      });
    }
  }

  @override
  void dispose() {
    _guestCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _nightlyCtrl.dispose();
    _advanceCtrl.dispose();
    _notesCtrl.dispose();
    _nationalityCtrl.dispose();
    _discountCtrl.dispose();
    _idTypeCtrl.dispose();
    _idNumberCtrl.dispose();
    _idIssuePlaceCtrl.dispose();
    _idIssueDateCtrl.dispose();
    super.dispose();
  }

  Set<String> get _occupiedRooms {
    final occupiedRooms = <String>{};
    for (final booking in _activeBookings) {
      if (widget.existing == null || booking.id != widget.existing!.id) {
        occupiedRooms.add(booking.roomNumber);
      }
    }
    return occupiedRooms;
  }

  bool get _isEdit => widget.existing != null;
  String get _title => _isEdit ? 'تعديل الحجز' : 'حجز جديد';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: scheme.background,
      appBar: _buildAppBar(context, scheme),
      body: _loadingRooms
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  _buildStepIndicator(scheme),
                  Expanded(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: _buildCurrentStep(scheme),
                        ),
                      ),
                    ),
                  ),
                  _buildNavigationButtons(scheme),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, ColorScheme scheme) {
    return AppBar(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _isEdit ? Icons.edit_calendar : Icons.add_business,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(_title),
        ],
      ),
      elevation: 0,
      actions: [
        if (_isEdit)
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _confirmDelete,
            tooltip: 'حذف الحجز',
          ),
      ],
    );
  }

  Widget _buildStepIndicator(ColorScheme scheme) {
    final steps = [
      {'icon': Icons.person, 'label': 'الضيف'},
      {'icon': Icons.hotel, 'label': 'الغرفة'},
      {'icon': Icons.payments, 'label': 'الدفع'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isActive = index == _currentStep;
          final isCompleted = index < _currentStep;

          return Expanded(
            child: Row(
              children: [
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: isCompleted || isActive
                            ? AppColors.primaryColor
                            : scheme.outline.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () => setState(() => _currentStep = index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primaryColor
                          : isCompleted
                              ? AppColors.primaryColor.withOpacity(0.15)
                              : scheme.surface,
                      borderRadius: BorderRadius.circular(25),
                      border: Border.all(
                        color: isActive || isCompleted
                            ? AppColors.primaryColor
                            : scheme.outline.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCompleted
                              ? Icons.check_circle
                              : steps[index]['icon'] as IconData,
                          size: 14,
                          color: isActive
                              ? Colors.white
                              : isCompleted
                                  ? AppColors.primaryColor
                                  : scheme.outline,
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 6),
                          Text(
                            steps[index]['label'] as String,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (index < steps.length - 1 && index == _currentStep)
                  const Spacer(),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCurrentStep(ColorScheme scheme) {
    switch (_currentStep) {
      case 0:
        return _buildGuestInfoStep(scheme);
      case 1:
        return _buildRoomStep(scheme);
      case 2:
        return _buildPaymentStep(scheme);
      default:
        return _buildGuestInfoStep(scheme);
    }
  }

  Widget _buildGuestInfoStep(ColorScheme scheme) {
    return Column(
      key: const ValueKey('guest'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.person,
          title: 'معلومات الضيف الأساسية',
          iconColor: AppColors.primaryColor,
          children: [
            _buildModernTextField(
              controller: _guestCtrl,
              label: 'اسم الضيف',
              icon: Icons.person_outline,
              validator: _req,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _phoneCtrl,
              label: 'رقم الهاتف',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _nationalityCtrl,
              label: 'الجنسية',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _addressCtrl,
              label: 'العنوان',
              icon: Icons.location_on_outlined,
              maxLines: 2,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.badge,
          title: 'بيانات الهوية',
          iconColor: AppColors.infoColor,
          isCollapsible: true,
          initiallyExpanded: _idNumberCtrl.text.isNotEmpty,
          children: [
            _buildModernTextField(
              controller: _idTypeCtrl,
              label: 'نوع الهوية',
              icon: Icons.credit_card_outlined,
              hint: 'بطاقة شخصية / جواز سفر',
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _idNumberCtrl,
              label: 'رقم الهوية',
              icon: Icons.numbers,
              keyboardType: TextInputType.text,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildModernTextField(
                    controller: _idIssueDateCtrl,
                    label: 'تاريخ الإصدار',
                    icon: Icons.calendar_today_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildModernTextField(
                    controller: _idIssuePlaceCtrl,
                    label: 'مكان الإصدار',
                    icon: Icons.place_outlined,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRoomStep(ColorScheme scheme) {
    return Column(
      key: const ValueKey('room'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.hotel,
          title: 'اختيار الغرفة',
          iconColor: AppColors.successColor,
          children: [
            _buildRoomSelector(scheme),
          ],
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.calendar_month,
          title: 'تواريخ الإقامة',
          iconColor: AppColors.warningColor,
          children: [
            _buildDateTimeSelector(scheme),
            const SizedBox(height: 10),
            _buildNightsSelector(scheme),
            const SizedBox(height: 8),
            _buildCheckoutPreview(scheme),
          ],
        ),
        const SizedBox(height: 8),
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.info_outline,
          title: 'حالة الحجز',
          iconColor: AppColors.infoColor,
          children: [
            _buildStatusSelector(scheme),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentStep(ColorScheme scheme) {
    final nightlyRate = double.tryParse(_nightlyCtrl.text) ?? 0;
    final discount = double.tryParse(_discountCtrl.text) ?? 0;
    final totalAmount = (nightlyRate * _expectedNights) - discount;
    final advance = double.tryParse(_advanceCtrl.text) ?? 0;
    final remaining = totalAmount - advance;

    return Column(
      key: const ValueKey('payment'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.attach_money,
          title: 'تفاصيل الأسعار',
          iconColor: AppColors.successColor,
          children: [
            _buildModernTextField(
              controller: _nightlyCtrl,
              label: 'سعر الليلة',
              icon: Icons.nightlight_outlined,
              keyboardType: TextInputType.number,
              validator: _req,
              suffix: 'ر.ي',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _discountCtrl,
              label: 'الخصم',
              icon: Icons.discount_outlined,
              keyboardType: TextInputType.number,
              suffix: 'ر.ي',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 8),
            _buildModernTextField(
              controller: _advanceCtrl,
              label: 'الدفعة المقدمة',
              icon: Icons.payments_outlined,
              keyboardType: TextInputType.number,
              suffix: 'ر.ي',
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildPriceSummaryCard(scheme, totalAmount, advance, remaining, discount),
        const SizedBox(height: 8),
        _buildSectionCard(
          scheme: scheme,
          icon: Icons.notes,
          title: 'ملاحظات',
          iconColor: AppColors.mediumGray,
          isCollapsible: true,
          initiallyExpanded: _notesCtrl.text.isNotEmpty,
          children: [
            _buildModernTextField(
              controller: _notesCtrl,
              label: 'ملاحظات إضافية',
              icon: Icons.edit_note,
              maxLines: 3,
              hint: 'أي ملاحظات خاصة بالحجز...',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionCard({
    required ColorScheme scheme,
    required IconData icon,
    required String title,
    required Color iconColor,
    required List<Widget> children,
    bool isCollapsible = false,
    bool initiallyExpanded = true,
  }) {
    if (isCollapsible) {
      return _CollapsibleSection(
        icon: icon,
        title: title,
        iconColor: iconColor,
        initiallyExpanded: initiallyExpanded,
        children: children,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outline.withOpacity(0.1)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? suffix,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        prefixIcon: Icon(icon, size: 16),
        filled: true,
        fillColor: AppColors.backgroundColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.lightGray, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.dangerColor, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildRoomSelector(ColorScheme scheme) {
    final availableRooms = _rooms.where((r) => !_occupiedRooms.contains(r.number)).toList();
    final occupiedRooms = _rooms.where((r) => _occupiedRooms.contains(r.number)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (availableRooms.isNotEmpty) ...[
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.successColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'الغرف المتاحة (${availableRooms.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableRooms.map((room) => _buildRoomChip(room, scheme, false)).toList(),
          ),
        ],
        if (occupiedRooms.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: AppColors.dangerColor,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'الغرف المشغولة (${occupiedRooms.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withOpacity(0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: occupiedRooms.map((room) => _buildRoomChip(room, scheme, true)).toList(),
          ),
        ],
        if (_selectedRoom == null && _rooms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'الرجاء اختيار غرفة',
              style: TextStyle(
                color: AppColors.dangerColor,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRoomChip(Room room, ColorScheme scheme, bool isOccupied) {
    final isSelected = _selectedRoom == room.number;
    final canSelect = !isOccupied || isSelected;

    return GestureDetector(
      onTap: canSelect ? () => setState(() => _selectedRoom = room.number) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryColor
              : isOccupied
                  ? scheme.surface
                  : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : isOccupied
                    ? AppColors.dangerColor.withOpacity(0.3)
                    : AppColors.lightGray,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(
              Icons.hotel,
              color: isSelected
                  ? Colors.white
                  : isOccupied
                      ? AppColors.dangerColor.withOpacity(0.5)
                      : AppColors.primaryColor,
              size: 20,
            ),
            const SizedBox(height: 2),
            Text(
              room.number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: isSelected
                    ? Colors.white
                    : isOccupied
                        ? scheme.onSurface.withOpacity(0.4)
                        : scheme.onSurface,
              ),
            ),
            if (room.floor != null)
              Text(
                'طابق ${room.floor}',
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? Colors.white.withOpacity(0.8)
                      : scheme.onSurface.withOpacity(0.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateTimeSelector(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: _buildDateTimeTile(
            scheme: scheme,
            icon: Icons.calendar_today,
            label: 'تاريخ الدخول',
            value: '${_checkinDate.day}/${_checkinDate.month}/${_checkinDate.year}',
            onTap: () => _selectDate(context),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildDateTimeTile(
            scheme: scheme,
            icon: Icons.access_time,
            label: 'وقت الدخول',
            value: _checkinTime.format(context),
            onTap: () => _selectTime(context),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeTile({
    required ColorScheme scheme,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.lightGray),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.primaryColor),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: scheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNightsSelector(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.nights_stay,
              color: AppColors.primaryColor,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عدد الليالي المتوقعة',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$_expectedNights ${_expectedNights == 1 ? 'ليلة' : 'ليالي'}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _buildNightButton(
                icon: Icons.remove,
                onTap: _expectedNights > 1
                    ? () => setState(() => _expectedNights--)
                    : null,
              ),
              Container(
                width: 50,
                alignment: Alignment.center,
                child: Text(
                  '$_expectedNights',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _buildNightButton(
                icon: Icons.add,
                onTap: () => setState(() => _expectedNights++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNightButton({
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return Material(
      color: isEnabled ? AppColors.primaryColor : AppColors.lightGray,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(
            icon,
            color: isEnabled ? Colors.white : AppColors.mediumGray,
            size: 20,
          ),
        ),
      ),
    );
  }

  Widget _buildCheckoutPreview(ColorScheme scheme) {
    final checkoutDate = _checkinDate.add(Duration(days: _expectedNights));
    
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.infoColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.logout,
            color: AppColors.infoColor,
            size: 20,
          ),
          const SizedBox(width: 10),
          Text(
            'تاريخ الخروج المتوقع:',
            style: TextStyle(
              fontSize: 13,
              color: scheme.onSurface.withOpacity(0.7),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${checkoutDate.day}/${checkoutDate.month}/${checkoutDate.year}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.infoColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSelector(ColorScheme scheme) {
    final statuses = [
      {'value': 'active', 'label': 'نشط', 'icon': Icons.check_circle, 'color': AppColors.successColor},
      {'value': 'reserved', 'label': 'محجوز', 'icon': Icons.schedule, 'color': AppColors.warningColor},
      {'value': 'checked_out', 'label': 'خرج', 'icon': Icons.logout, 'color': AppColors.infoColor},
      {'value': 'cancelled', 'label': 'ملغي', 'icon': Icons.cancel, 'color': AppColors.dangerColor},
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: statuses.map((status) {
        final isSelected = _selectedStatus == status['value'];
        final color = status['color'] as Color;

        return GestureDetector(
          onTap: () => setState(() => _selectedStatus = status['value'] as String),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? color : scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : color.withOpacity(0.3),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  status['icon'] as IconData,
                  size: 18,
                  color: isSelected ? Colors.white : color,
                ),
                const SizedBox(width: 8),
                Text(
                  status['label'] as String,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : color,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPriceSummaryCard(
    ColorScheme scheme,
    double total,
    double advance,
    double remaining,
    double discount,
  ) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryColor,
            AppColors.primaryDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.receipt_long,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ملخص الفاتورة',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSummaryRow('سعر الليلة × $_expectedNights', '${(double.tryParse(_nightlyCtrl.text) ?? 0) * _expectedNights}'),
            if (discount > 0)
              _buildSummaryRow('الخصم', '-$discount', isDiscount: true),
            _buildSummaryRow('الدفعة المقدمة', '-$advance'),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: Colors.white24, height: 1),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'المتبقي',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                Text(
                  '${remaining.toStringAsFixed(0)} ر.ي',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: remaining > 0 ? Colors.white : AppColors.successColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isDiscount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.8),
            ),
          ),
          Text(
            '$value ر.ي',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDiscount ? Colors.greenAccent : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons(ColorScheme scheme) {
    final isLastStep = _currentStep == 2;
    final isFirstStep = _currentStep == 0;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!isFirstStep)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('السابق'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: const BorderSide(color: AppColors.primaryColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            if (!isFirstStep) const SizedBox(width: 8),
            Expanded(
              flex: isFirstStep ? 1 : 1,
              child: ElevatedButton.icon(
                onPressed: _saving
                    ? null
                    : isLastStep
                        ? _submit
                        : () => _validateAndNext(),
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(isLastStep ? Icons.check : Icons.arrow_forward),
                label: Text(
                  _saving
                      ? 'جاري الحفظ...'
                      : isLastStep
                          ? (_isEdit ? 'تحديث الحجز' : 'إنشاء الحجز')
                          : 'التالي',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLastStep ? AppColors.successColor : AppColors.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _validateAndNext() {
    if (_currentStep == 0) {
      if (_guestCtrl.text.trim().isEmpty) {
        _showError('الرجاء إدخال اسم الضيف');
        return;
      }
    } else if (_currentStep == 1) {
      if (_selectedRoom == null) {
        _showError('الرجاء اختيار غرفة');
        return;
      }
    }
    setState(() => _currentStep++);
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _checkinDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _checkinDate = picked);
    }
  }

  Future<void> _selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _checkinTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: AppColors.primaryColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _checkinTime = picked);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: AppColors.dangerColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.dangerColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.delete_forever, color: AppColors.dangerColor),
            ),
            const SizedBox(width: 8),
            const Text('حذف الحجز'),
          ],
        ),
        content: const Text('هل أنت متأكد من حذف هذا الحجز؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dangerColor,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _deleteBooking();
    }
  }

  Future<void> _deleteBooking() async {
    if (widget.existing == null) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(bookingsRepoProvider);
      await repo.delete(widget.existing!.id);
      markDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('تم حذف الحجز بنجاح'),
              ],
            ),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('فشل في حذف الحجز: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoom == null) {
      _showError('الرجاء اختيار غرفة');
      setState(() => _currentStep = 1);
      return;
    }
    if (_nightlyCtrl.text.trim().isEmpty) {
      _showError('الرجاء إدخال سعر الليلة');
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(bookingsRepoProvider);
      final checkinDateTime = DateTime(
        _checkinDate.year,
        _checkinDate.month,
        _checkinDate.day,
        _checkinTime.hour,
        _checkinTime.minute,
      );

      final companion = BookingsCompanion(
        guestName: drift.Value(_guestCtrl.text.trim()),
        guestPhone: drift.Value(_optionalText(_phoneCtrl.text)),
        guestAddress: drift.Value(_optionalText(_addressCtrl.text)),
        guestNationality: drift.Value(_optionalText(_nationalityCtrl.text)),
        guestIdType: drift.Value(_optionalText(_idTypeCtrl.text)),
        guestIdNumber: drift.Value(_optionalText(_idNumberCtrl.text)),
        guestIdIssuePlace: drift.Value(_optionalText(_idIssuePlaceCtrl.text)),
        guestIdIssueDate: drift.Value(_optionalText(_idIssueDateCtrl.text)),
        roomNumber: drift.Value(_selectedRoom!),
        checkinDate: drift.Value(checkinDateTime),
        nightlyRate: drift.Value(double.tryParse(_nightlyCtrl.text) ?? 0),
        advancePayment: drift.Value(double.tryParse(_advanceCtrl.text) ?? 0),
        discount: drift.Value(double.tryParse(_discountCtrl.text)),
        status: drift.Value(_selectedStatus),
        notes: drift.Value(_optionalText(_notesCtrl.text)),
        expectedNights: drift.Value(_expectedNights),
      );

      if (_isEdit) {
        await repo.update(widget.existing!.id, companion);
      } else {
        await repo.insert(companion);
      }

      markDataChanged();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(_isEdit ? 'تم تحديث الحجز بنجاح' : 'تم إنشاء الحجز بنجاح'),
              ],
            ),
            backgroundColor: AppColors.successColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showError('فشل في حفظ الحجز: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _optionalText(String text) =>
      text.trim().isEmpty ? null : text.trim();
  String? _req(String? v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null;
}

class _CollapsibleSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final Color iconColor;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _CollapsibleSection({
    required this.icon,
    required this.title,
    required this.iconColor,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  State<_CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<_CollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _iconTurns;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _iconTurns = Tween<double>(begin: 0.0, end: 0.5).animate(_controller);
    if (_isExpanded) _controller.value = 1.0;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: widget.iconColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(widget.icon, color: widget.iconColor, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: _iconTurns,
                    child: Icon(
                      Icons.expand_more,
                      color: scheme.onSurface.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  Divider(height: 1, color: scheme.outline.withOpacity(0.1)),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: widget.children,
                    ),
                  ),
                ],
              ),
              crossFadeState: _isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    );
  }
}
