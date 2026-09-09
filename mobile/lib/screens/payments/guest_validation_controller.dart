/// Guest validation and management for booking payments.
///
/// Extracted from booking_payment_screen.dart (4,118 LOC)
/// This module handles guest data validation and debt management.

import '../../services/local_db.dart' as db;

/// Guest validation controller
class GuestValidationController {
  /// Validate guest name
  static bool validateGuestName(String name) {
    return name.isNotEmpty && name.length >= 2;
  }

  /// Validate phone number format
  static bool validatePhoneNumber(String phone) {
    // Support Yemeni phone numbers
    if (phone.isEmpty) return false;
    if (phone.length < 7) return false;
    if (phone.length > 12) return false;

    // Remove common prefixes
    var normalized = phone;
    if (normalized.startsWith('+')) normalized = normalized.substring(1);
    if (normalized.startsWith('00')) normalized = normalized.substring(2);

    // Must be digits only
    return RegExp(r'^\d{7,12}$').hasMatch(normalized);
  }

  /// Validate guest ID/Passport
  static bool validateGuestId(String id) {
    return id.isNotEmpty && id.length >= 2;
  }

  /// Validate email format
  static bool validateEmail(String email) {
    if (email.isEmpty) return true; // Optional field
    return RegExp(r'^[a-zA-Z0-9._%-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$')
        .hasMatch(email);
  }

  /// Sanitize phone number for storage
  static String sanitizePhone(String phone) {
    var result = phone.trim();

    // Remove common prefixes
    if (result.startsWith('+')) result = result.substring(1);
    if (result.startsWith('00')) result = result.substring(2);

    // Keep only digits
    result = result.replaceAll(RegExp(r'\D'), '');

    // Remove leading zeros for Yemeni format
    while (result.startsWith('0') && result.length > 9) {
      result = result.substring(1);
    }

    return result;
  }

  /// Calculate total unsettled debt for guest
  static double calculateTotalDebt(List<db.Debt> debts) {
    return debts.fold<double>(0, (sum, debt) => sum + (debt.amount ?? 0));
  }

  /// Filter unsettled debts (not yet paid)
  static List<db.Debt> getUnsettledDebts(List<db.Debt> debts) {
    return debts.where((d) => d.isSettled != 1).toList();
  }

  /// Get debts for specific booking
  static List<db.Debt> getDebtsForBooking({
    required int bookingId,
    required List<db.Debt> allDebts,
  }) {
    return allDebts.where((d) => d.bookingLocalId == bookingId).toList();
  }

  /// Check if guest can pay via specific method
  static bool canPayViaMethod({
    required String paymentMethod,
    required double amount,
    required String guestPhone,
  }) {
    // Cash: no limits
    if (paymentMethod == 'نقدي' || paymentMethod == 'نقداً') {
      return true;
    }

    // Card: needs valid phone
    if (paymentMethod == 'بطاقة' || paymentMethod == 'بطاقة ائتمان') {
      return validatePhoneNumber(guestPhone) && amount > 0;
    }

    // Bank transfer: needs contact info
    if (paymentMethod == 'تحويل بنكي') {
      return validatePhoneNumber(guestPhone);
    }

    return false;
  }

  /// Map payment method from database to UI
  static String mapPaymentMethod(String dbMethod) {
    switch (dbMethod) {
      case 'نقدي':
      case 'نقداً':
        return 'Cash';
      case 'بطاقة':
      case 'بطاقة ائتمان':
        return 'Card';
      case 'تحويل بنكي':
        return 'Bank Transfer';
      default:
        return dbMethod;
    }
  }

  /// Validate guest data completeness
  static ValidateResult validateGuestData({
    required String name,
    required String phone,
    required String email,
    required String idNumber,
    bool requirePhone = true,
    bool requireEmail = false,
  }) {
    if (!validateGuestName(name)) {
      return const ValidateResult(
        isValid: false,
        error: 'Name must be at least 2 characters',
      );
    }

    if (requirePhone && !validatePhoneNumber(phone)) {
      return const ValidateResult(
        isValid: false,
        error: 'Phone number is invalid',
      );
    }

    if (requireEmail && !validateEmail(email)) {
      return const ValidateResult(
        isValid: false,
        error: 'Email address is invalid',
      );
    }

    if (idNumber.isNotEmpty && !validateGuestId(idNumber)) {
      return const ValidateResult(
        isValid: false,
        error: 'ID number is invalid',
      );
    }

    return const ValidateResult(isValid: true);
  }
}

/// Validation result
class ValidateResult {
  const ValidateResult({
    required this.isValid,
    this.error = '',
  });

  final bool isValid;
  final String error;
}
