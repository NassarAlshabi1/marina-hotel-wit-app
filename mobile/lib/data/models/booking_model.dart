import 'package:hive/hive.dart';
import 'package:equatable/equatable.dart';

part 'booking_model.g.dart';

@HiveType(typeId: 0)
class BookingModel extends Equatable {
  @HiveField(0)
  final String id;
  
  @HiveField(1)
  final String guestName;
  
  @HiveField(2)
  final DateTime checkIn;
  
  @HiveField(3)
  final DateTime checkOut;
  
  @HiveField(4)
  final double nightlyRate;
  
  @HiveField(5)
  final String roomType;
  
  @HiveField(6)
  final List<String> bookedSlips;
  
  @HiveField(7)
  final DateTime createdAt;

  const BookingModel({
    required this.id,
    required this.guestName,
    required this.checkIn,
    required this.checkOut,
    required this.nightlyRate,
    required this.roomType,
    this.bookedSlips = const [],
    required this.createdAt,
  });

  /// Calculate total price
  double get totalPrice {
    final nights = checkOut.difference(checkIn).inDays;
    return nightlyRate * nights;
  }

  /// Number of nights
  int get nights => checkOut.difference(checkIn).inDays;

  /// Copy with new values
  BookingModel copyWith({
    String? id,
    String? guestName,
    DateTime? checkIn,
    DateTime? checkOut,
    double? nightlyRate,
    String? roomType,
    List<String>? bookedSlips,
    DateTime? createdAt,
  }) {
    return BookingModel(
      id: id ?? this.id,
      guestName: guestName ?? this.guestName,
      checkIn: checkIn ?? this.checkIn,
      checkOut: checkOut ?? this.checkOut,
      nightlyRate: nightlyRate ?? this.nightlyRate,
      roomType: roomType ?? this.roomType,
      bookedSlips: bookedSlips ?? this.bookedSlips,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'guestName': guestName,
    'checkIn': checkIn.toIso8601String(),
    'checkOut': checkOut.toIso8601String(),
    'nightlyRate': nightlyRate,
    'roomType': roomType,
    'bookedSlips': bookedSlips,
    'createdAt': createdAt.toIso8601String(),
  };

  /// Create from JSON
  factory BookingModel.fromJson(Map<String, dynamic> json) => BookingModel(
    id: json['id'] as String,
    guestName: json['guestName'] as String,
    checkIn: DateTime.parse(json['checkIn'] as String),
    checkOut: DateTime.parse(json['checkOut'] as String),
    nightlyRate: (json['nightlyRate'] as num).toDouble(),
    roomType: json['roomType'] as String,
    bookedSlips: List<String>.from(json['bookedSlips'] ?? []),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  @override
  List<Object?> get props => [
    id,
    guestName,
    checkIn,
    checkOut,
    nightlyRate,
    roomType,
    bookedSlips,
    createdAt,
  ];
}