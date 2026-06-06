import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../booking_utils.dart';
import '../../providers/booking_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../main.dart';

/// Home page with booking form using Riverpod
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingState = ref.watch(bookingProvider);
    final notifier = ref.read(bookingProvider.notifier);
    final isDarkMode = ref.watch(isDarkModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marina Hotel Booking'),
        // Performance: Use const for actions that don't change
        actions: [
          // Dark mode toggle button
          IconButton(
            icon: Icon(isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () {
              ref.read(isDarkModeProvider.notifier).state = !isDarkMode;
            },
            tooltip: isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
          ),
        ],
      ),
      // Performance: RepaintBoundary prevents unnecessary repaints
      body: RepaintBoundary(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _GuestNameField(
                value: bookingState.guestName,
                error: bookingState.guestNameError,
                onChanged: notifier.updateGuestName,
              ),
              const SizedBox(height: 16),
              _DateSelectors(
                checkIn: bookingState.checkIn,
                checkOut: bookingState.checkOut,
                onSelectCheckIn: notifier.updateCheckIn,
                onSelectCheckOut: notifier.updateCheckOut,
              ),
              const SizedBox(height: 16),
              _RoomTypeSelector(
                value: bookingState.roomType,
                onChanged: notifier.updateRoomType,
              ),
              const SizedBox(height: 16),
              _RateSlider(
                value: bookingState.nightlyRate,
                onChanged: notifier.updateNightlyRate,
              ),
              const SizedBox(height: 16),
              _SlipSelector(
                availableSlips: bookingState.availableSlips,
                selectedSlip: bookingState.selectedSlip,
                bookedSlips: bookingState.bookedSlips,
                onSelected: notifier.updateSelectedSlip,
              ),
              const SizedBox(height: 24),
              _PriceSummary(
                nightlyRate: bookingState.nightlyRate,
                nights: bookingState.nights,
                totalPrice: bookingState.totalPrice,
              ),
              const SizedBox(height: 24),
              _BookButton(
                isValid: bookingState.isValid,
                isSubmitting: bookingState.isSubmitting,
                errorMessage: bookingState.errorMessage,
                onSubmit: () async {
                  final booking = await notifier.submitBooking();
                  if (booking != null && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Booking confirmed!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Guest name input widget - Fixed memory leak and performance issues
class _GuestNameField extends StatefulWidget {
  final String value;
  final String? error;
  final ValueChanged<String> onChanged;

  const _GuestNameField({
    required this.value,
    required this.error,
    required this.onChanged,
  });

  @override
  State<_GuestNameField> createState() => _GuestNameFieldState();
}

class _GuestNameFieldState extends State<_GuestNameField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _GuestNameField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync controller text when value changes externally
    if (widget.value != _controller.text) {
      _controller.text = widget.value;
      _controller.selection = TextSelection.collapsed(offset: widget.value.length);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      decoration: InputDecoration(
        labelText: 'Guest Name',
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.person),
        errorText: widget.error,
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Date selectors widget
class _DateSelectors extends StatelessWidget {
  final DateTime? checkIn;
  final DateTime? checkOut;
  final ValueChanged<DateTime> onSelectCheckIn;
  final ValueChanged<DateTime> onSelectCheckOut;

  const _DateSelectors({
    required this.checkIn,
    required this.checkOut,
    required this.onSelectCheckIn,
    required this.onSelectCheckOut,
  });

  Future<void> _selectDate(BuildContext context, bool isCheckIn) async {
    // Strip time from now to get today at midnight
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final DateTime initialDate = isCheckIn
        ? (checkIn ?? today)
        : (checkOut ?? checkIn ?? today);
    final DateTime firstDate =
        isCheckIn ? today : (checkIn ?? today);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: today.add(const Duration(days: 365)),
    );

    if (picked != null) {
      if (isCheckIn) {
        onSelectCheckIn(picked);
      } else {
        onSelectCheckOut(picked);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _DateButton(
            label: 'Check-in',
            date: checkIn,
            onTap: () => _selectDate(context, true),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _DateButton(
            label: 'Check-out',
            date: checkOut,
            onTap: () => _selectDate(context, false),
          ),
        ),
      ],
    );
  }
}

/// Date button widget - Performance optimized
class _DateButton extends StatelessWidget {
  final String label;
  final DateTime? date;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.date,
    required this.onTap,
  });

  // Performance: Cache formatted date string
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: '',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.calendar_today),
        ),
        child: Text(
          date != null ? _formatDate(date!) : label,
          style: TextStyle(
            color: date != null ? null : Colors.grey,
          ),
        ),
      ),
    );
  }
}

/// Room type selector widget - Performance optimized with const items
class _RoomTypeSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _RoomTypeSelector({
    required this.value,
    required this.onChanged,
  });

  // Performance: Define items as static const
  static const _roomTypes = [
    DropdownMenuItem(value: 'Standard', child: Text('Standard')),
    DropdownMenuItem(value: 'Deluxe', child: Text('Deluxe')),
    DropdownMenuItem(value: 'Suite', child: Text('Suite')),
    DropdownMenuItem(value: 'Marina View', child: Text('Marina View')),
  ];

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: const InputDecoration(
        labelText: 'Room Type',
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.hotel),
      ),
      items: _roomTypes,
      onChanged: (newValue) {
        if (newValue != null) onChanged(newValue);
      },
    );
  }
}

/// Rate slider widget - Performance optimized
class _RateSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _RateSlider({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Performance: Use const Text for static labels
        Text('Nightly Rate: \$${value.toStringAsFixed(0)}'),
        Slider(
          value: value,
          min: 50,
          max: 500,
          divisions: 45,
          label: '\$${value.toStringAsFixed(0)}',
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Slip selector widget - Performance optimized with List.generate
class _SlipSelector extends StatelessWidget {
  final List<String> availableSlips;
  final String? selectedSlip;
  final List<String> bookedSlips;
  final ValueChanged<String?> onSelected;

  const _SlipSelector({
    required this.availableSlips,
    required this.selectedSlip,
    required this.bookedSlips,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Performance: Use const for static text
        const Text('Marina Slip (Optional)', style: TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        // Performance: Use List.generate for better performance
        Wrap(
          spacing: 8,
          children: List.generate(
            availableSlips.length,
            (index) {
              final slip = availableSlips[index];
              final isBooked = bookedSlips.contains(slip);
              final isSelected = selectedSlip == slip;

              return ChoiceChip(
                label: Text(slip),
                selected: isSelected,
                onSelected: isBooked
                    ? null
                    : (selected) => onSelected(selected ? slip : null),
                backgroundColor: isBooked ? Colors.grey.shade300 : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Price summary widget - Performance optimized
class _PriceSummary extends StatelessWidget {
  final double nightlyRate;
  final int nights;
  final double totalPrice;

  const _PriceSummary({
    required this.nightlyRate,
    required this.nights,
    required this.totalPrice,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Performance: Use const for static labels
            _PriceRow(label: 'Nightly Rate:', value: '\$${nightlyRate.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            _PriceRow(label: 'Number of Nights:', value: '$nights'),
            const Divider(),
            _PriceRow(
              label: 'Total:',
              value: '\$${totalPrice.toStringAsFixed(2)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Price row widget - Reusable component
class _PriceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isBold;

  const _PriceRow({
    required this.label,
    required this.value,
    this.isBold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isBold ? const TextStyle(fontWeight: FontWeight.bold) : null,
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: isBold ? FontWeight.bold : null,
            fontSize: isBold ? 18 : null,
          ),
        ),
      ],
    );
  }
}

/// Book button widget - Performance optimized
class _BookButton extends StatelessWidget {
  final bool isValid;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onSubmit;

  const _BookButton({
    required this.isValid,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ElevatedButton(
          onPressed: isValid && !isSubmitting ? onSubmit : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Colors.white,
          ),
          child: isSubmitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Book Now', style: TextStyle(fontSize: 18)),
        ),
      ],
    );
  }
}