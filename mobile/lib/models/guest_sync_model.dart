import 'package:mongo_dart/mongo_dart.dart';

class GuestSync {
  final ObjectId? id;
  final String guestId;
  final String fullName;
  final String phone;
  final String? email;
  final String? idNumber;
  final String? nationality;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  GuestSync({
    this.id,
    required this.guestId,
    required this.fullName,
    required this.phone,
    this.email,
    this.idNumber,
    this.nationality,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
  });

  Map<String, dynamic> toMongo() {
    return {
      if (id != null) '_id': id,
      'guest_id': guestId,
      'full_name': fullName,
      'phone': phone,
      'email': email,
      'id_number': idNumber,
      'nationality': nationality,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory GuestSync.fromMongo(Map<String, dynamic> json) {
    return GuestSync(
      id: json['_id'] as ObjectId?,
      guestId: json['guest_id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String,
      email: json['email'] as String?,
      idNumber: json['id_number'] as String?,
      nationality: json['nationality'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deviceId: json['device_id'] as String,
    );
  }

  GuestSync copyWith({
    ObjectId? id,
    String? guestId,
    String? fullName,
    String? phone,
    String? email,
    String? idNumber,
    String? nationality,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? deviceId,
  }) {
    return GuestSync(
      id: id ?? this.id,
      guestId: guestId ?? this.guestId,
      fullName: fullName ?? this.fullName,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      idNumber: idNumber ?? this.idNumber,
      nationality: nationality ?? this.nationality,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deviceId: deviceId ?? this.deviceId,
    );
  }
}

class BookingSync {
  final ObjectId? id;
  final String bookingId;
  final String guestName;
  final String roomNumber;
  final String status;
  final DateTime checkInDate;
  final DateTime checkOutDate;
  final double totalAmount;
  final double paidAmount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String deviceId;

  BookingSync({
    this.id,
    required this.bookingId,
    required this.guestName,
    required this.roomNumber,
    required this.status,
    required this.checkInDate,
    required this.checkOutDate,
    required this.totalAmount,
    required this.paidAmount,
    required this.createdAt,
    required this.updatedAt,
    required this.deviceId,
  });

  Map<String, dynamic> toMongo() {
    return {
      if (id != null) '_id': id,
      'booking_id': bookingId,
      'guest_name': guestName,
      'room_number': roomNumber,
      'status': status,
      'check_in_date': checkInDate.toIso8601String(),
      'check_out_date': checkOutDate.toIso8601String(),
      'total_amount': totalAmount,
      'paid_amount': paidAmount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'device_id': deviceId,
    };
  }

  factory BookingSync.fromMongo(Map<String, dynamic> json) {
    return BookingSync(
      id: json['_id'] as ObjectId?,
      bookingId: json['booking_id'] as String,
      guestName: json['guest_name'] as String,
      roomNumber: json['room_number'] as String,
      status: json['status'] as String,
      checkInDate: DateTime.parse(json['check_in_date'] as String),
      checkOutDate: DateTime.parse(json['check_out_date'] as String),
      totalAmount: (json['total_amount'] as num).toDouble(),
      paidAmount: (json['paid_amount'] as num).toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deviceId: json['device_id'] as String,
    );
  }
}
