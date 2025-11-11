import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/providers.dart';
import 'guest_info.dart';

class GuestEditScreen extends ConsumerStatefulWidget {
  const GuestEditScreen({super.key, required this.guest});

  final GuestInfo guest;

  @override
  ConsumerState<GuestEditScreen> createState() => _GuestEditScreenState();
}

class _GuestEditScreenState extends ConsumerState<GuestEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _nationalityController;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.guest.name);
    _phoneController = TextEditingController(text: widget.guest.phone);
    _emailController = TextEditingController(text: widget.guest.email);
    _nationalityController = TextEditingController(text: widget.guest.nationality);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _nationalityController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    final bookingsRepo = ref.read(bookingsRepoProvider);
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final email = _emailController.text.trim();
    final nationality = _nationalityController.text.trim();

    try {
      for (final booking in widget.guest.bookings) {
        await bookingsRepo.update(
          booking.id,
          guestName: name,
          guestPhone: phone,
          guestEmail: email.isNotEmpty ? email : null,
          guestNationality: nationality.isNotEmpty ? nationality : null,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر حفظ التغييرات: $error'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تعديل بيانات الضيف'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveChanges,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(widget.guest.name),
                  subtitle: Text('عدد الحجوزات: ${widget.guest.bookings.length}'),
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _nameController,
                label: 'اسم الضيف',
                icon: Icons.person,
                validator: (value) => value == null || value.trim().isEmpty ? 'الاسم مطلوب' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _phoneController,
                label: 'رقم الهاتف',
                icon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().isEmpty ? 'رقم الهاتف مطلوب' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                label: 'البريد الإلكتروني (اختياري)',
                icon: Icons.email,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) return null;
                  final emailRegex = RegExp(r'^.+@.+\..+$');
                  if (!emailRegex.hasMatch(value)) {
                    return 'صيغة بريد غير صحيحة';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _nationalityController,
                label: 'الجنسية',
                icon: Icons.flag,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _saveChanges,
                icon: const Icon(Icons.save),
                label: const Text('حفظ التعديلات'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
      ),
    );
  }
}
