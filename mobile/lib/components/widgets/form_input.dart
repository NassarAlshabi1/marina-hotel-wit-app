import 'package:flutter/material.dart';

class FormInput extends StatelessWidget {
  const FormInput({super.key, required this.controller, required this.label, this.obscureText = false, this.keyboardType});
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
    );
  }
}
