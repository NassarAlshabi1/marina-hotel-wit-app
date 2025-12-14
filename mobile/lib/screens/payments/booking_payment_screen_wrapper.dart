import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/local_db.dart' as db;
import 'booking_payment_screen.dart';

/// Wrapper للتحقق من عمل شاشة معالجة المدفوعات
/// يمكن استخدام هذا الـ Wrapper لاكتشاف الأخطاء
class BookingPaymentScreenWrapper extends ConsumerWidget {
  final db.Booking booking;
  
  const BookingPaymentScreenWrapper({
    super.key,
    required this.booking,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ErrorBoundary(
      child: BookingPaymentScreen(booking: booking),
    );
  }
}

/// Error Boundary للتقاط الأخطاء
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  
  const ErrorBoundary({
    super.key,
    required this.child,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? error;
  StackTrace? stackTrace;

  @override
  void initState() {
    super.initState();
    
    FlutterError.onError = (FlutterErrorDetails details) {
      if (mounted) {
        setState(() {
          error = details.exception;
          stackTrace = details.stack;
        });
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('خطأ في الشاشة'),
          backgroundColor: Colors.red,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'حدث خطأ في شاشة معالجة المدفوعات',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'تفاصيل الخطأ:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    error.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
                if (stackTrace != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Stack Trace:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      stackTrace.toString(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            error = null;
                            stackTrace = null;
                          });
                        },
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('رجوع'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}

/// Helper function لفتح شاشة معالجة المدفوعات بشكل آمن
void openBookingPaymentScreen(BuildContext context, db.Booking booking) {
  try {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BookingPaymentScreenWrapper(booking: booking),
      ),
    );
  } catch (e, stackTrace) {
    debugPrint('Error opening payment screen: $e');
    debugPrint('Stack trace: $stackTrace');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('خطأ في فتح شاشة المدفوعات: ${e.toString()}'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'تفاصيل',
          textColor: Colors.white,
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('تفاصيل الخطأ'),
                content: SingleChildScrollView(
                  child: Text('$e\n\n$stackTrace'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إغلاق'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
