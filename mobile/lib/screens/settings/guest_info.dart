import '../../services/local_db.dart';

class GuestInfo {
  final String name;
  final String phone;
  final String email;
  final String nationality;
  final List<Booking> bookings;

  const GuestInfo({
    required this.name,
    required this.phone,
    required this.email,
    required this.nationality,
    required this.bookings,
  });

  GuestInfo copyWith({
    String? name,
    String? phone,
    String? email,
    String? nationality,
    List<Booking>? bookings,
  }) {
    return GuestInfo(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      nationality: nationality ?? this.nationality,
      bookings: bookings ?? this.bookings,
    );
  }
}
