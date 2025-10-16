import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'utils/theme.dart';
import 'screens/booking_list_screen.dart';

void main() {
  runApp(const BookingMockApp());
}

class BookingMockApp extends StatelessWidget {
  const BookingMockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مارينا هوتيل',
      theme: buildTheme(),
      locale: const Locale('ar'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar')],
      home: const BookingListScreen(),
    );
  }
}
