import '../../services/local_db.dart';

class GuestInfo {
  GuestInfo({
    required this.name,
    required this.phone,
    required this.email,
    required this.nationality,
    required this.idType,
    required this.idNumber,
    this.idIssueDate,
    this.idIssuePlace,
    this.address,
    List<Booking>? bookings,
  }) : bookings = bookings ?? [];

  String name;
  String phone;
  String email;
  String nationality;
  String idType;
  String idNumber;
  String? idIssueDate;
  String? idIssuePlace;
  String? address;
  final List<Booking> bookings;
}
