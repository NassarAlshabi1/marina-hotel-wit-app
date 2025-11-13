import '../../services/local_db.dart';

class GuestInfo {
  final String name;
  final String phone;
  final String email;
  final String nationality;
  final String idType;
  final String idNumber;
  final String? idIssueDate;
  final String? idIssuePlace;
  final String? address;
  final List<Booking> bookings;

  const GuestInfo({
    required this.name,
    required this.phone,
    required this.email,
    required this.nationality,
    required this.idType,
    required this.idNumber,
    this.idIssueDate,
    this.idIssuePlace,
    this.address,
    required this.bookings,
  });

  GuestInfo copyWith({
    String? name,
    String? phone,
    String? email,
    String? nationality,
    String? idType,
    String? idNumber,
    String? idIssueDate,
    String? idIssuePlace,
    String? address,
    List<Booking>? bookings,
  }) {
    return GuestInfo(
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      nationality: nationality ?? this.nationality,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      idIssueDate: idIssueDate ?? this.idIssueDate,
      idIssuePlace: idIssuePlace ?? this.idIssuePlace,
      address: address ?? this.address,
      bookings: bookings ?? this.bookings,
    );
  }
}
