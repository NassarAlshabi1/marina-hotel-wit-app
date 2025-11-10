import 'package:flutter/material.dart';

class RealtimeStatusIndicator extends StatelessWidget {
  const RealtimeStatusIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return const Tooltip(
      message: 'تم تعطيل المزامنة السحابية',
      child: Icon(Icons.cloud_off, color: Colors.grey, size: 20),
    );
  }
}
