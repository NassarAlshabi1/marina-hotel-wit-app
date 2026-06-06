// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'booking_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class BookingModelAdapter extends TypeAdapter<BookingModel> {
  @override
  final int typeId = 0;

  @override
  BookingModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return BookingModel(
      id: fields[0] as String,
      guestName: fields[1] as String,
      checkIn: fields[2] as DateTime,
      checkOut: fields[3] as DateTime,
      nightlyRate: fields[4] as double,
      roomType: fields[5] as String,
      bookedSlips: (fields[6] as List).cast<String>(),
      createdAt: fields[7] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, BookingModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.guestName)
      ..writeByte(2)
      ..write(obj.checkIn)
      ..writeByte(3)
      ..write(obj.checkOut)
      ..writeByte(4)
      ..write(obj.nightlyRate)
      ..writeByte(5)
      ..write(obj.roomType)
      ..writeByte(6)
      ..write(obj.bookedSlips)
      ..writeByte(7)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}