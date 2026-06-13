---
Task ID: 1
Agent: Main Agent
Task: إصلاح حساب المدفوعات والمتبقي والأيام والليالي في الالتزام

Work Log:
- استنساخ المستودع وتحليل هيكل المشروع (Flutter/Dart مع Drift ORM)
- تحليل ثلاثة مسارات حساب مختلفة (EnhancedBookingCalculationService, BookingComputedStreamService, BookingPaymentScreen)
- اكتشاف عدم توافق في حساب المبلغ الإجمالي بين المسارات الثلاثة
- اكتشاف عدم فلترة الدفعات الملغاة (voided) والمعلقة (pending) في عدة شاشات
- إصلاح BookingComputedStreamService لاستخدام EnhancedBookingCalculationService كمرجع موحد
- إصلاح bookings_list.dart لاستخدام القيم المحسوبة مسبقاً (cached) بدلاً من إعادة الحساب
- إصلاح فلترة الدفعات في: booking_payment_screen, booking_checkout_screen, payment_history_screen, payments_main_screen, finance_screen, payments_list, payments_report_screen, income_expense_report_screen
- إضافة عرض الأيام والليالي بشكل منفصل في شاشة الدفع
- إضافة getter `nights` في BookingWithPayments للتوحيد

Stage Summary:
- تم توحيد مسار الحساب ليكون EnhancedBookingCalculationService هو المصدر الموحد
- تم إصلاح فلترة المدفوعات (voided + pending) في 8 ملفات مختلفة
- تم إضافة عرض الأيام التقويمية والليالي الفندقية بشكل منفصل
- الملفات المعدلة: booking_computed_stream_service.dart, bookings_list.dart, booking_payment_screen.dart, booking_checkout_screen.dart, payment_history_screen.dart, payments_main_screen.dart, finance_screen.dart, payments_list.dart, payments_report_screen.dart, income_expense_report_screen.dart
