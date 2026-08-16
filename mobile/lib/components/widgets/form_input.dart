import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/english_digits_input_formatter.dart';

class FormInput extends StatelessWidget {
  const FormInput({
    required this.controller,
    required this.label,
    super.key,
    this.obscureText = false,
    this.keyboardType,
    this.inputFormatters,
  });
  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      inputFormatters:
          inputFormatters ??
          ((keyboardType == TextInputType.number ||
                  keyboardType == TextInputType.phone)
              ? const [englishIntegerInputFormatter]
              : null),
      decoration: InputDecoration(labelText: label),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
    );
  }
}
