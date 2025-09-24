// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_db.dart';

// ignore_for_file: type=lint
class $RoomsTable extends Rooms with TableInfo<$RoomsTable, Room> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _roomNumberMeta =
      const VerificationMeta('roomNumber');
  @override
  late final GeneratedColumn<String> roomNumber = GeneratedColumn<String>(
      'room_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _priceMeta = const VerificationMeta('price');
  @override
  late final GeneratedColumn<double> price = GeneratedColumn<double>(
      'price', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _imageUrlMeta =
      const VerificationMeta('imageUrl');
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
      'image_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        roomNumber,
        type,
        price,
        status,
        imageUrl
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(Insertable<Room> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('room_number')) {
      context.handle(
          _roomNumberMeta,
          roomNumber.isAcceptableOrUnknown(
              data['room_number']!, _roomNumberMeta));
    } else if (isInserting) {
      context.missing(_roomNumberMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('price')) {
      context.handle(
          _priceMeta, price.isAcceptableOrUnknown(data['price']!, _priceMeta));
    } else if (isInserting) {
      context.missing(_priceMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('image_url')) {
      context.handle(_imageUrlMeta,
          imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roomNumber};
  @override
  Room map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Room(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      roomNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}room_number'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
      price: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}price'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      imageUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}image_url']),
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }
}

class Room extends DataClass implements Insertable<Room> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final String roomNumber;
  final String type;
  final double price;
  final String status;
  final String? imageUrl;
  const Room(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.roomNumber,
      required this.type,
      required this.price,
      required this.status,
      this.imageUrl});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['room_number'] = Variable<String>(roomNumber);
    map['type'] = Variable<String>(type);
    map['price'] = Variable<double>(price);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      roomNumber: Value(roomNumber),
      type: Value(type),
      price: Value(price),
      status: Value(status),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
    );
  }

  factory Room.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Room(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      roomNumber: serializer.fromJson<String>(json['roomNumber']),
      type: serializer.fromJson<String>(json['type']),
      price: serializer.fromJson<double>(json['price']),
      status: serializer.fromJson<String>(json['status']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'roomNumber': serializer.toJson<String>(roomNumber),
      'type': serializer.toJson<String>(type),
      'price': serializer.toJson<double>(price),
      'status': serializer.toJson<String>(status),
      'imageUrl': serializer.toJson<String?>(imageUrl),
    };
  }

  Room copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          String? roomNumber,
          String? type,
          double? price,
          String? status,
          Value<String?> imageUrl = const Value.absent()}) =>
      Room(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        roomNumber: roomNumber ?? this.roomNumber,
        type: type ?? this.type,
        price: price ?? this.price,
        status: status ?? this.status,
        imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
      );
  Room copyWithCompanion(RoomsCompanion data) {
    return Room(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      roomNumber:
          data.roomNumber.present ? data.roomNumber.value : this.roomNumber,
      type: data.type.present ? data.type.value : this.type,
      price: data.price.present ? data.price.value : this.price,
      status: data.status.present ? data.status.value : this.status,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Room(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('type: $type, ')
          ..write('price: $price, ')
          ..write('status: $status, ')
          ..write('imageUrl: $imageUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localUuid,
      serverId,
      createdAt,
      updatedAt,
      deletedAt,
      lastModified,
      version,
      origin,
      roomNumber,
      type,
      price,
      status,
      imageUrl);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Room &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.roomNumber == this.roomNumber &&
          other.type == this.type &&
          other.price == this.price &&
          other.status == this.status &&
          other.imageUrl == this.imageUrl);
}

class RoomsCompanion extends UpdateCompanion<Room> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<String> roomNumber;
  final Value<String> type;
  final Value<double> price;
  final Value<String> status;
  final Value<String?> imageUrl;
  final Value<int> rowid;
  const RoomsCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.roomNumber = const Value.absent(),
    this.type = const Value.absent(),
    this.price = const Value.absent(),
    this.status = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomsCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    required String roomNumber,
    required String type,
    required double price,
    required String status,
    this.imageUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        roomNumber = Value(roomNumber),
        type = Value(type),
        price = Value(price),
        status = Value(status);
  static Insertable<Room> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<String>? roomNumber,
    Expression<String>? type,
    Expression<double>? price,
    Expression<String>? status,
    Expression<String>? imageUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (roomNumber != null) 'room_number': roomNumber,
      if (type != null) 'type': type,
      if (price != null) 'price': price,
      if (status != null) 'status': status,
      if (imageUrl != null) 'image_url': imageUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomsCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<String>? roomNumber,
      Value<String>? type,
      Value<double>? price,
      Value<String>? status,
      Value<String?>? imageUrl,
      Value<int>? rowid}) {
    return RoomsCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      roomNumber: roomNumber ?? this.roomNumber,
      type: type ?? this.type,
      price: price ?? this.price,
      status: status ?? this.status,
      imageUrl: imageUrl ?? this.imageUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (roomNumber.present) {
      map['room_number'] = Variable<String>(roomNumber.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (price.present) {
      map['price'] = Variable<double>(price.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('type: $type, ')
          ..write('price: $price, ')
          ..write('status: $status, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookingsTable extends Bookings with TableInfo<$BookingsTable, Booking> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverBookingIdMeta =
      const VerificationMeta('serverBookingId');
  @override
  late final GeneratedColumn<int> serverBookingId = GeneratedColumn<int>(
      'server_booking_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _roomNumberMeta =
      const VerificationMeta('roomNumber');
  @override
  late final GeneratedColumn<String> roomNumber = GeneratedColumn<String>(
      'room_number', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES rooms (room_number)'));
  static const VerificationMeta _guestNameMeta =
      const VerificationMeta('guestName');
  @override
  late final GeneratedColumn<String> guestName = GeneratedColumn<String>(
      'guest_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _guestPhoneMeta =
      const VerificationMeta('guestPhone');
  @override
  late final GeneratedColumn<String> guestPhone = GeneratedColumn<String>(
      'guest_phone', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _guestNationalityMeta =
      const VerificationMeta('guestNationality');
  @override
  late final GeneratedColumn<String> guestNationality = GeneratedColumn<String>(
      'guest_nationality', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _guestEmailMeta =
      const VerificationMeta('guestEmail');
  @override
  late final GeneratedColumn<String> guestEmail = GeneratedColumn<String>(
      'guest_email', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _guestAddressMeta =
      const VerificationMeta('guestAddress');
  @override
  late final GeneratedColumn<String> guestAddress = GeneratedColumn<String>(
      'guest_address', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _checkinDateMeta =
      const VerificationMeta('checkinDate');
  @override
  late final GeneratedColumn<String> checkinDate = GeneratedColumn<String>(
      'checkin_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _checkoutDateMeta =
      const VerificationMeta('checkoutDate');
  @override
  late final GeneratedColumn<String> checkoutDate = GeneratedColumn<String>(
      'checkout_date', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _calculatedNightsMeta =
      const VerificationMeta('calculatedNights');
  @override
  late final GeneratedColumn<int> calculatedNights = GeneratedColumn<int>(
      'calculated_nights', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        serverBookingId,
        roomNumber,
        guestName,
        guestPhone,
        guestNationality,
        guestEmail,
        guestAddress,
        checkinDate,
        checkoutDate,
        status,
        notes,
        calculatedNights
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookings';
  @override
  VerificationContext validateIntegrity(Insertable<Booking> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_booking_id')) {
      context.handle(
          _serverBookingIdMeta,
          serverBookingId.isAcceptableOrUnknown(
              data['server_booking_id']!, _serverBookingIdMeta));
    }
    if (data.containsKey('room_number')) {
      context.handle(
          _roomNumberMeta,
          roomNumber.isAcceptableOrUnknown(
              data['room_number']!, _roomNumberMeta));
    } else if (isInserting) {
      context.missing(_roomNumberMeta);
    }
    if (data.containsKey('guest_name')) {
      context.handle(_guestNameMeta,
          guestName.isAcceptableOrUnknown(data['guest_name']!, _guestNameMeta));
    } else if (isInserting) {
      context.missing(_guestNameMeta);
    }
    if (data.containsKey('guest_phone')) {
      context.handle(
          _guestPhoneMeta,
          guestPhone.isAcceptableOrUnknown(
              data['guest_phone']!, _guestPhoneMeta));
    } else if (isInserting) {
      context.missing(_guestPhoneMeta);
    }
    if (data.containsKey('guest_nationality')) {
      context.handle(
          _guestNationalityMeta,
          guestNationality.isAcceptableOrUnknown(
              data['guest_nationality']!, _guestNationalityMeta));
    } else if (isInserting) {
      context.missing(_guestNationalityMeta);
    }
    if (data.containsKey('guest_email')) {
      context.handle(
          _guestEmailMeta,
          guestEmail.isAcceptableOrUnknown(
              data['guest_email']!, _guestEmailMeta));
    }
    if (data.containsKey('guest_address')) {
      context.handle(
          _guestAddressMeta,
          guestAddress.isAcceptableOrUnknown(
              data['guest_address']!, _guestAddressMeta));
    }
    if (data.containsKey('checkin_date')) {
      context.handle(
          _checkinDateMeta,
          checkinDate.isAcceptableOrUnknown(
              data['checkin_date']!, _checkinDateMeta));
    } else if (isInserting) {
      context.missing(_checkinDateMeta);
    }
    if (data.containsKey('checkout_date')) {
      context.handle(
          _checkoutDateMeta,
          checkoutDate.isAcceptableOrUnknown(
              data['checkout_date']!, _checkoutDateMeta));
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('calculated_nights')) {
      context.handle(
          _calculatedNightsMeta,
          calculatedNights.isAcceptableOrUnknown(
              data['calculated_nights']!, _calculatedNightsMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Booking map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Booking(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverBookingId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_booking_id']),
      roomNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}room_number'])!,
      guestName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guest_name'])!,
      guestPhone: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guest_phone'])!,
      guestNationality: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}guest_nationality'])!,
      guestEmail: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guest_email']),
      guestAddress: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}guest_address']),
      checkinDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}checkin_date'])!,
      checkoutDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}checkout_date']),
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      calculatedNights: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}calculated_nights'])!,
    );
  }

  @override
  $BookingsTable createAlias(String alias) {
    return $BookingsTable(attachedDatabase, alias);
  }
}

class Booking extends DataClass implements Insertable<Booking> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final int? serverBookingId;
  final String roomNumber;
  final String guestName;
  final String guestPhone;
  final String guestNationality;
  final String? guestEmail;
  final String? guestAddress;
  final String checkinDate;
  final String? checkoutDate;
  final String status;
  final String? notes;
  final int calculatedNights;
  const Booking(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      this.serverBookingId,
      required this.roomNumber,
      required this.guestName,
      required this.guestPhone,
      required this.guestNationality,
      this.guestEmail,
      this.guestAddress,
      required this.checkinDate,
      this.checkoutDate,
      required this.status,
      this.notes,
      required this.calculatedNights});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || serverBookingId != null) {
      map['server_booking_id'] = Variable<int>(serverBookingId);
    }
    map['room_number'] = Variable<String>(roomNumber);
    map['guest_name'] = Variable<String>(guestName);
    map['guest_phone'] = Variable<String>(guestPhone);
    map['guest_nationality'] = Variable<String>(guestNationality);
    if (!nullToAbsent || guestEmail != null) {
      map['guest_email'] = Variable<String>(guestEmail);
    }
    if (!nullToAbsent || guestAddress != null) {
      map['guest_address'] = Variable<String>(guestAddress);
    }
    map['checkin_date'] = Variable<String>(checkinDate);
    if (!nullToAbsent || checkoutDate != null) {
      map['checkout_date'] = Variable<String>(checkoutDate);
    }
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['calculated_nights'] = Variable<int>(calculatedNights);
    return map;
  }

  BookingsCompanion toCompanion(bool nullToAbsent) {
    return BookingsCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      serverBookingId: serverBookingId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverBookingId),
      roomNumber: Value(roomNumber),
      guestName: Value(guestName),
      guestPhone: Value(guestPhone),
      guestNationality: Value(guestNationality),
      guestEmail: guestEmail == null && nullToAbsent
          ? const Value.absent()
          : Value(guestEmail),
      guestAddress: guestAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(guestAddress),
      checkinDate: Value(checkinDate),
      checkoutDate: checkoutDate == null && nullToAbsent
          ? const Value.absent()
          : Value(checkoutDate),
      status: Value(status),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      calculatedNights: Value(calculatedNights),
    );
  }

  factory Booking.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Booking(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      serverBookingId: serializer.fromJson<int?>(json['serverBookingId']),
      roomNumber: serializer.fromJson<String>(json['roomNumber']),
      guestName: serializer.fromJson<String>(json['guestName']),
      guestPhone: serializer.fromJson<String>(json['guestPhone']),
      guestNationality: serializer.fromJson<String>(json['guestNationality']),
      guestEmail: serializer.fromJson<String?>(json['guestEmail']),
      guestAddress: serializer.fromJson<String?>(json['guestAddress']),
      checkinDate: serializer.fromJson<String>(json['checkinDate']),
      checkoutDate: serializer.fromJson<String?>(json['checkoutDate']),
      status: serializer.fromJson<String>(json['status']),
      notes: serializer.fromJson<String?>(json['notes']),
      calculatedNights: serializer.fromJson<int>(json['calculatedNights']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'serverBookingId': serializer.toJson<int?>(serverBookingId),
      'roomNumber': serializer.toJson<String>(roomNumber),
      'guestName': serializer.toJson<String>(guestName),
      'guestPhone': serializer.toJson<String>(guestPhone),
      'guestNationality': serializer.toJson<String>(guestNationality),
      'guestEmail': serializer.toJson<String?>(guestEmail),
      'guestAddress': serializer.toJson<String?>(guestAddress),
      'checkinDate': serializer.toJson<String>(checkinDate),
      'checkoutDate': serializer.toJson<String?>(checkoutDate),
      'status': serializer.toJson<String>(status),
      'notes': serializer.toJson<String?>(notes),
      'calculatedNights': serializer.toJson<int>(calculatedNights),
    };
  }

  Booking copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          Value<int?> serverBookingId = const Value.absent(),
          String? roomNumber,
          String? guestName,
          String? guestPhone,
          String? guestNationality,
          Value<String?> guestEmail = const Value.absent(),
          Value<String?> guestAddress = const Value.absent(),
          String? checkinDate,
          Value<String?> checkoutDate = const Value.absent(),
          String? status,
          Value<String?> notes = const Value.absent(),
          int? calculatedNights}) =>
      Booking(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        serverBookingId: serverBookingId.present
            ? serverBookingId.value
            : this.serverBookingId,
        roomNumber: roomNumber ?? this.roomNumber,
        guestName: guestName ?? this.guestName,
        guestPhone: guestPhone ?? this.guestPhone,
        guestNationality: guestNationality ?? this.guestNationality,
        guestEmail: guestEmail.present ? guestEmail.value : this.guestEmail,
        guestAddress:
            guestAddress.present ? guestAddress.value : this.guestAddress,
        checkinDate: checkinDate ?? this.checkinDate,
        checkoutDate:
            checkoutDate.present ? checkoutDate.value : this.checkoutDate,
        status: status ?? this.status,
        notes: notes.present ? notes.value : this.notes,
        calculatedNights: calculatedNights ?? this.calculatedNights,
      );
  Booking copyWithCompanion(BookingsCompanion data) {
    return Booking(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      serverBookingId: data.serverBookingId.present
          ? data.serverBookingId.value
          : this.serverBookingId,
      roomNumber:
          data.roomNumber.present ? data.roomNumber.value : this.roomNumber,
      guestName: data.guestName.present ? data.guestName.value : this.guestName,
      guestPhone:
          data.guestPhone.present ? data.guestPhone.value : this.guestPhone,
      guestNationality: data.guestNationality.present
          ? data.guestNationality.value
          : this.guestNationality,
      guestEmail:
          data.guestEmail.present ? data.guestEmail.value : this.guestEmail,
      guestAddress: data.guestAddress.present
          ? data.guestAddress.value
          : this.guestAddress,
      checkinDate:
          data.checkinDate.present ? data.checkinDate.value : this.checkinDate,
      checkoutDate: data.checkoutDate.present
          ? data.checkoutDate.value
          : this.checkoutDate,
      status: data.status.present ? data.status.value : this.status,
      notes: data.notes.present ? data.notes.value : this.notes,
      calculatedNights: data.calculatedNights.present
          ? data.calculatedNights.value
          : this.calculatedNights,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Booking(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('serverBookingId: $serverBookingId, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('guestName: $guestName, ')
          ..write('guestPhone: $guestPhone, ')
          ..write('guestNationality: $guestNationality, ')
          ..write('guestEmail: $guestEmail, ')
          ..write('guestAddress: $guestAddress, ')
          ..write('checkinDate: $checkinDate, ')
          ..write('checkoutDate: $checkoutDate, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('calculatedNights: $calculatedNights')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        serverBookingId,
        roomNumber,
        guestName,
        guestPhone,
        guestNationality,
        guestEmail,
        guestAddress,
        checkinDate,
        checkoutDate,
        status,
        notes,
        calculatedNights
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Booking &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.serverBookingId == this.serverBookingId &&
          other.roomNumber == this.roomNumber &&
          other.guestName == this.guestName &&
          other.guestPhone == this.guestPhone &&
          other.guestNationality == this.guestNationality &&
          other.guestEmail == this.guestEmail &&
          other.guestAddress == this.guestAddress &&
          other.checkinDate == this.checkinDate &&
          other.checkoutDate == this.checkoutDate &&
          other.status == this.status &&
          other.notes == this.notes &&
          other.calculatedNights == this.calculatedNights);
}

class BookingsCompanion extends UpdateCompanion<Booking> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<int?> serverBookingId;
  final Value<String> roomNumber;
  final Value<String> guestName;
  final Value<String> guestPhone;
  final Value<String> guestNationality;
  final Value<String?> guestEmail;
  final Value<String?> guestAddress;
  final Value<String> checkinDate;
  final Value<String?> checkoutDate;
  final Value<String> status;
  final Value<String?> notes;
  final Value<int> calculatedNights;
  const BookingsCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.serverBookingId = const Value.absent(),
    this.roomNumber = const Value.absent(),
    this.guestName = const Value.absent(),
    this.guestPhone = const Value.absent(),
    this.guestNationality = const Value.absent(),
    this.guestEmail = const Value.absent(),
    this.guestAddress = const Value.absent(),
    this.checkinDate = const Value.absent(),
    this.checkoutDate = const Value.absent(),
    this.status = const Value.absent(),
    this.notes = const Value.absent(),
    this.calculatedNights = const Value.absent(),
  });
  BookingsCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.serverBookingId = const Value.absent(),
    required String roomNumber,
    required String guestName,
    required String guestPhone,
    required String guestNationality,
    this.guestEmail = const Value.absent(),
    this.guestAddress = const Value.absent(),
    required String checkinDate,
    this.checkoutDate = const Value.absent(),
    required String status,
    this.notes = const Value.absent(),
    this.calculatedNights = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        roomNumber = Value(roomNumber),
        guestName = Value(guestName),
        guestPhone = Value(guestPhone),
        guestNationality = Value(guestNationality),
        checkinDate = Value(checkinDate),
        status = Value(status);
  static Insertable<Booking> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<int>? serverBookingId,
    Expression<String>? roomNumber,
    Expression<String>? guestName,
    Expression<String>? guestPhone,
    Expression<String>? guestNationality,
    Expression<String>? guestEmail,
    Expression<String>? guestAddress,
    Expression<String>? checkinDate,
    Expression<String>? checkoutDate,
    Expression<String>? status,
    Expression<String>? notes,
    Expression<int>? calculatedNights,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (serverBookingId != null) 'server_booking_id': serverBookingId,
      if (roomNumber != null) 'room_number': roomNumber,
      if (guestName != null) 'guest_name': guestName,
      if (guestPhone != null) 'guest_phone': guestPhone,
      if (guestNationality != null) 'guest_nationality': guestNationality,
      if (guestEmail != null) 'guest_email': guestEmail,
      if (guestAddress != null) 'guest_address': guestAddress,
      if (checkinDate != null) 'checkin_date': checkinDate,
      if (checkoutDate != null) 'checkout_date': checkoutDate,
      if (status != null) 'status': status,
      if (notes != null) 'notes': notes,
      if (calculatedNights != null) 'calculated_nights': calculatedNights,
    });
  }

  BookingsCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<int?>? serverBookingId,
      Value<String>? roomNumber,
      Value<String>? guestName,
      Value<String>? guestPhone,
      Value<String>? guestNationality,
      Value<String?>? guestEmail,
      Value<String?>? guestAddress,
      Value<String>? checkinDate,
      Value<String?>? checkoutDate,
      Value<String>? status,
      Value<String?>? notes,
      Value<int>? calculatedNights}) {
    return BookingsCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      serverBookingId: serverBookingId ?? this.serverBookingId,
      roomNumber: roomNumber ?? this.roomNumber,
      guestName: guestName ?? this.guestName,
      guestPhone: guestPhone ?? this.guestPhone,
      guestNationality: guestNationality ?? this.guestNationality,
      guestEmail: guestEmail ?? this.guestEmail,
      guestAddress: guestAddress ?? this.guestAddress,
      checkinDate: checkinDate ?? this.checkinDate,
      checkoutDate: checkoutDate ?? this.checkoutDate,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      calculatedNights: calculatedNights ?? this.calculatedNights,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverBookingId.present) {
      map['server_booking_id'] = Variable<int>(serverBookingId.value);
    }
    if (roomNumber.present) {
      map['room_number'] = Variable<String>(roomNumber.value);
    }
    if (guestName.present) {
      map['guest_name'] = Variable<String>(guestName.value);
    }
    if (guestPhone.present) {
      map['guest_phone'] = Variable<String>(guestPhone.value);
    }
    if (guestNationality.present) {
      map['guest_nationality'] = Variable<String>(guestNationality.value);
    }
    if (guestEmail.present) {
      map['guest_email'] = Variable<String>(guestEmail.value);
    }
    if (guestAddress.present) {
      map['guest_address'] = Variable<String>(guestAddress.value);
    }
    if (checkinDate.present) {
      map['checkin_date'] = Variable<String>(checkinDate.value);
    }
    if (checkoutDate.present) {
      map['checkout_date'] = Variable<String>(checkoutDate.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (calculatedNights.present) {
      map['calculated_nights'] = Variable<int>(calculatedNights.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookingsCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('serverBookingId: $serverBookingId, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('guestName: $guestName, ')
          ..write('guestPhone: $guestPhone, ')
          ..write('guestNationality: $guestNationality, ')
          ..write('guestEmail: $guestEmail, ')
          ..write('guestAddress: $guestAddress, ')
          ..write('checkinDate: $checkinDate, ')
          ..write('checkoutDate: $checkoutDate, ')
          ..write('status: $status, ')
          ..write('notes: $notes, ')
          ..write('calculatedNights: $calculatedNights')
          ..write(')'))
        .toString();
  }
}

class $BookingNotesTable extends BookingNotes
    with TableInfo<$BookingNotesTable, BookingNote> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookingNotesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _bookingIdMeta =
      const VerificationMeta('bookingId');
  @override
  late final GeneratedColumn<int> bookingId = GeneratedColumn<int>(
      'booking_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES bookings (id)'));
  static const VerificationMeta _noteTextMeta =
      const VerificationMeta('noteText');
  @override
  late final GeneratedColumn<String> noteText = GeneratedColumn<String>(
      'note_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _alertTypeMeta =
      const VerificationMeta('alertType');
  @override
  late final GeneratedColumn<String> alertType = GeneratedColumn<String>(
      'alert_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _alertUntilMeta =
      const VerificationMeta('alertUntil');
  @override
  late final GeneratedColumn<String> alertUntil = GeneratedColumn<String>(
      'alert_until', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isActiveMeta =
      const VerificationMeta('isActive');
  @override
  late final GeneratedColumn<int> isActive = GeneratedColumn<int>(
      'is_active', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        bookingId,
        noteText,
        alertType,
        alertUntil,
        isActive
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'booking_notes';
  @override
  VerificationContext validateIntegrity(Insertable<BookingNote> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('booking_id')) {
      context.handle(_bookingIdMeta,
          bookingId.isAcceptableOrUnknown(data['booking_id']!, _bookingIdMeta));
    } else if (isInserting) {
      context.missing(_bookingIdMeta);
    }
    if (data.containsKey('note_text')) {
      context.handle(_noteTextMeta,
          noteText.isAcceptableOrUnknown(data['note_text']!, _noteTextMeta));
    } else if (isInserting) {
      context.missing(_noteTextMeta);
    }
    if (data.containsKey('alert_type')) {
      context.handle(_alertTypeMeta,
          alertType.isAcceptableOrUnknown(data['alert_type']!, _alertTypeMeta));
    } else if (isInserting) {
      context.missing(_alertTypeMeta);
    }
    if (data.containsKey('alert_until')) {
      context.handle(
          _alertUntilMeta,
          alertUntil.isAcceptableOrUnknown(
              data['alert_until']!, _alertUntilMeta));
    }
    if (data.containsKey('is_active')) {
      context.handle(_isActiveMeta,
          isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  BookingNote map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookingNote(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      bookingId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}booking_id'])!,
      noteText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}note_text'])!,
      alertType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alert_type'])!,
      alertUntil: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}alert_until']),
      isActive: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_active'])!,
    );
  }

  @override
  $BookingNotesTable createAlias(String alias) {
    return $BookingNotesTable(attachedDatabase, alias);
  }
}

class BookingNote extends DataClass implements Insertable<BookingNote> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final int bookingId;
  final String noteText;
  final String alertType;
  final String? alertUntil;
  final int isActive;
  const BookingNote(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      required this.bookingId,
      required this.noteText,
      required this.alertType,
      this.alertUntil,
      required this.isActive});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    map['booking_id'] = Variable<int>(bookingId);
    map['note_text'] = Variable<String>(noteText);
    map['alert_type'] = Variable<String>(alertType);
    if (!nullToAbsent || alertUntil != null) {
      map['alert_until'] = Variable<String>(alertUntil);
    }
    map['is_active'] = Variable<int>(isActive);
    return map;
  }

  BookingNotesCompanion toCompanion(bool nullToAbsent) {
    return BookingNotesCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      bookingId: Value(bookingId),
      noteText: Value(noteText),
      alertType: Value(alertType),
      alertUntil: alertUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(alertUntil),
      isActive: Value(isActive),
    );
  }

  factory BookingNote.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookingNote(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      bookingId: serializer.fromJson<int>(json['bookingId']),
      noteText: serializer.fromJson<String>(json['noteText']),
      alertType: serializer.fromJson<String>(json['alertType']),
      alertUntil: serializer.fromJson<String?>(json['alertUntil']),
      isActive: serializer.fromJson<int>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'bookingId': serializer.toJson<int>(bookingId),
      'noteText': serializer.toJson<String>(noteText),
      'alertType': serializer.toJson<String>(alertType),
      'alertUntil': serializer.toJson<String?>(alertUntil),
      'isActive': serializer.toJson<int>(isActive),
    };
  }

  BookingNote copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          int? bookingId,
          String? noteText,
          String? alertType,
          Value<String?> alertUntil = const Value.absent(),
          int? isActive}) =>
      BookingNote(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        bookingId: bookingId ?? this.bookingId,
        noteText: noteText ?? this.noteText,
        alertType: alertType ?? this.alertType,
        alertUntil: alertUntil.present ? alertUntil.value : this.alertUntil,
        isActive: isActive ?? this.isActive,
      );
  BookingNote copyWithCompanion(BookingNotesCompanion data) {
    return BookingNote(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      bookingId: data.bookingId.present ? data.bookingId.value : this.bookingId,
      noteText: data.noteText.present ? data.noteText.value : this.noteText,
      alertType: data.alertType.present ? data.alertType.value : this.alertType,
      alertUntil:
          data.alertUntil.present ? data.alertUntil.value : this.alertUntil,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookingNote(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('bookingId: $bookingId, ')
          ..write('noteText: $noteText, ')
          ..write('alertType: $alertType, ')
          ..write('alertUntil: $alertUntil, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localUuid,
      serverId,
      createdAt,
      updatedAt,
      deletedAt,
      lastModified,
      version,
      origin,
      id,
      bookingId,
      noteText,
      alertType,
      alertUntil,
      isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookingNote &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.bookingId == this.bookingId &&
          other.noteText == this.noteText &&
          other.alertType == this.alertType &&
          other.alertUntil == this.alertUntil &&
          other.isActive == this.isActive);
}

class BookingNotesCompanion extends UpdateCompanion<BookingNote> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<int> bookingId;
  final Value<String> noteText;
  final Value<String> alertType;
  final Value<String?> alertUntil;
  final Value<int> isActive;
  const BookingNotesCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.bookingId = const Value.absent(),
    this.noteText = const Value.absent(),
    this.alertType = const Value.absent(),
    this.alertUntil = const Value.absent(),
    this.isActive = const Value.absent(),
  });
  BookingNotesCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    required int bookingId,
    required String noteText,
    required String alertType,
    this.alertUntil = const Value.absent(),
    this.isActive = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        bookingId = Value(bookingId),
        noteText = Value(noteText),
        alertType = Value(alertType);
  static Insertable<BookingNote> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<int>? bookingId,
    Expression<String>? noteText,
    Expression<String>? alertType,
    Expression<String>? alertUntil,
    Expression<int>? isActive,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (bookingId != null) 'booking_id': bookingId,
      if (noteText != null) 'note_text': noteText,
      if (alertType != null) 'alert_type': alertType,
      if (alertUntil != null) 'alert_until': alertUntil,
      if (isActive != null) 'is_active': isActive,
    });
  }

  BookingNotesCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<int>? bookingId,
      Value<String>? noteText,
      Value<String>? alertType,
      Value<String?>? alertUntil,
      Value<int>? isActive}) {
    return BookingNotesCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      bookingId: bookingId ?? this.bookingId,
      noteText: noteText ?? this.noteText,
      alertType: alertType ?? this.alertType,
      alertUntil: alertUntil ?? this.alertUntil,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (bookingId.present) {
      map['booking_id'] = Variable<int>(bookingId.value);
    }
    if (noteText.present) {
      map['note_text'] = Variable<String>(noteText.value);
    }
    if (alertType.present) {
      map['alert_type'] = Variable<String>(alertType.value);
    }
    if (alertUntil.present) {
      map['alert_until'] = Variable<String>(alertUntil.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<int>(isActive.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookingNotesCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('bookingId: $bookingId, ')
          ..write('noteText: $noteText, ')
          ..write('alertType: $alertType, ')
          ..write('alertUntil: $alertUntil, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }
}

class $EmployeesTable extends Employees
    with TableInfo<$EmployeesTable, Employee> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EmployeesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _basicSalaryMeta =
      const VerificationMeta('basicSalary');
  @override
  late final GeneratedColumn<double> basicSalary = GeneratedColumn<double>(
      'basic_salary', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
      'status', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        name,
        basicSalary,
        status
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'employees';
  @override
  VerificationContext validateIntegrity(Insertable<Employee> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('basic_salary')) {
      context.handle(
          _basicSalaryMeta,
          basicSalary.isAcceptableOrUnknown(
              data['basic_salary']!, _basicSalaryMeta));
    } else if (isInserting) {
      context.missing(_basicSalaryMeta);
    }
    if (data.containsKey('status')) {
      context.handle(_statusMeta,
          status.isAcceptableOrUnknown(data['status']!, _statusMeta));
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Employee map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Employee(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      basicSalary: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}basic_salary'])!,
      status: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
    );
  }

  @override
  $EmployeesTable createAlias(String alias) {
    return $EmployeesTable(attachedDatabase, alias);
  }
}

class Employee extends DataClass implements Insertable<Employee> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final String name;
  final double basicSalary;
  final String status;
  const Employee(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      required this.name,
      required this.basicSalary,
      required this.status});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['basic_salary'] = Variable<double>(basicSalary);
    map['status'] = Variable<String>(status);
    return map;
  }

  EmployeesCompanion toCompanion(bool nullToAbsent) {
    return EmployeesCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      name: Value(name),
      basicSalary: Value(basicSalary),
      status: Value(status),
    );
  }

  factory Employee.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Employee(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      basicSalary: serializer.fromJson<double>(json['basicSalary']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'basicSalary': serializer.toJson<double>(basicSalary),
      'status': serializer.toJson<String>(status),
    };
  }

  Employee copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          String? name,
          double? basicSalary,
          String? status}) =>
      Employee(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        name: name ?? this.name,
        basicSalary: basicSalary ?? this.basicSalary,
        status: status ?? this.status,
      );
  Employee copyWithCompanion(EmployeesCompanion data) {
    return Employee(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      basicSalary:
          data.basicSalary.present ? data.basicSalary.value : this.basicSalary,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Employee(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('basicSalary: $basicSalary, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(localUuid, serverId, createdAt, updatedAt,
      deletedAt, lastModified, version, origin, id, name, basicSalary, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Employee &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.name == this.name &&
          other.basicSalary == this.basicSalary &&
          other.status == this.status);
}

class EmployeesCompanion extends UpdateCompanion<Employee> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<String> name;
  final Value<double> basicSalary;
  final Value<String> status;
  const EmployeesCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.basicSalary = const Value.absent(),
    this.status = const Value.absent(),
  });
  EmployeesCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    required String name,
    required double basicSalary,
    required String status,
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        name = Value(name),
        basicSalary = Value(basicSalary),
        status = Value(status);
  static Insertable<Employee> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<String>? name,
    Expression<double>? basicSalary,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (basicSalary != null) 'basic_salary': basicSalary,
      if (status != null) 'status': status,
    });
  }

  EmployeesCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<String>? name,
      Value<double>? basicSalary,
      Value<String>? status}) {
    return EmployeesCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      name: name ?? this.name,
      basicSalary: basicSalary ?? this.basicSalary,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (basicSalary.present) {
      map['basic_salary'] = Variable<double>(basicSalary.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EmployeesCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('basicSalary: $basicSalary, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _expenseTypeMeta =
      const VerificationMeta('expenseType');
  @override
  late final GeneratedColumn<String> expenseType = GeneratedColumn<String>(
      'expense_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _relatedIdMeta =
      const VerificationMeta('relatedId');
  @override
  late final GeneratedColumn<int> relatedId = GeneratedColumn<int>(
      'related_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<String> date = GeneratedColumn<String>(
      'date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cashTransactionIdMeta =
      const VerificationMeta('cashTransactionId');
  @override
  late final GeneratedColumn<int> cashTransactionId = GeneratedColumn<int>(
      'cash_transaction_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        expenseType,
        relatedId,
        description,
        amount,
        date,
        cashTransactionId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(Insertable<Expense> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expense_type')) {
      context.handle(
          _expenseTypeMeta,
          expenseType.isAcceptableOrUnknown(
              data['expense_type']!, _expenseTypeMeta));
    } else if (isInserting) {
      context.missing(_expenseTypeMeta);
    }
    if (data.containsKey('related_id')) {
      context.handle(_relatedIdMeta,
          relatedId.isAcceptableOrUnknown(data['related_id']!, _relatedIdMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
          _dateMeta, date.isAcceptableOrUnknown(data['date']!, _dateMeta));
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('cash_transaction_id')) {
      context.handle(
          _cashTransactionIdMeta,
          cashTransactionId.isAcceptableOrUnknown(
              data['cash_transaction_id']!, _cashTransactionIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      expenseType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}expense_type'])!,
      relatedId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}related_id']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      date: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}date'])!,
      cashTransactionId: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}cash_transaction_id']),
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final String expenseType;
  final int? relatedId;
  final String description;
  final double amount;
  final String date;
  final int? cashTransactionId;
  const Expense(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      required this.expenseType,
      this.relatedId,
      required this.description,
      required this.amount,
      required this.date,
      this.cashTransactionId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    map['expense_type'] = Variable<String>(expenseType);
    if (!nullToAbsent || relatedId != null) {
      map['related_id'] = Variable<int>(relatedId);
    }
    map['description'] = Variable<String>(description);
    map['amount'] = Variable<double>(amount);
    map['date'] = Variable<String>(date);
    if (!nullToAbsent || cashTransactionId != null) {
      map['cash_transaction_id'] = Variable<int>(cashTransactionId);
    }
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      expenseType: Value(expenseType),
      relatedId: relatedId == null && nullToAbsent
          ? const Value.absent()
          : Value(relatedId),
      description: Value(description),
      amount: Value(amount),
      date: Value(date),
      cashTransactionId: cashTransactionId == null && nullToAbsent
          ? const Value.absent()
          : Value(cashTransactionId),
    );
  }

  factory Expense.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      expenseType: serializer.fromJson<String>(json['expenseType']),
      relatedId: serializer.fromJson<int?>(json['relatedId']),
      description: serializer.fromJson<String>(json['description']),
      amount: serializer.fromJson<double>(json['amount']),
      date: serializer.fromJson<String>(json['date']),
      cashTransactionId: serializer.fromJson<int?>(json['cashTransactionId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'expenseType': serializer.toJson<String>(expenseType),
      'relatedId': serializer.toJson<int?>(relatedId),
      'description': serializer.toJson<String>(description),
      'amount': serializer.toJson<double>(amount),
      'date': serializer.toJson<String>(date),
      'cashTransactionId': serializer.toJson<int?>(cashTransactionId),
    };
  }

  Expense copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          String? expenseType,
          Value<int?> relatedId = const Value.absent(),
          String? description,
          double? amount,
          String? date,
          Value<int?> cashTransactionId = const Value.absent()}) =>
      Expense(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        expenseType: expenseType ?? this.expenseType,
        relatedId: relatedId.present ? relatedId.value : this.relatedId,
        description: description ?? this.description,
        amount: amount ?? this.amount,
        date: date ?? this.date,
        cashTransactionId: cashTransactionId.present
            ? cashTransactionId.value
            : this.cashTransactionId,
      );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      expenseType:
          data.expenseType.present ? data.expenseType.value : this.expenseType,
      relatedId: data.relatedId.present ? data.relatedId.value : this.relatedId,
      description:
          data.description.present ? data.description.value : this.description,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      cashTransactionId: data.cashTransactionId.present
          ? data.cashTransactionId.value
          : this.cashTransactionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('expenseType: $expenseType, ')
          ..write('relatedId: $relatedId, ')
          ..write('description: $description, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('cashTransactionId: $cashTransactionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localUuid,
      serverId,
      createdAt,
      updatedAt,
      deletedAt,
      lastModified,
      version,
      origin,
      id,
      expenseType,
      relatedId,
      description,
      amount,
      date,
      cashTransactionId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.expenseType == this.expenseType &&
          other.relatedId == this.relatedId &&
          other.description == this.description &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.cashTransactionId == this.cashTransactionId);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<String> expenseType;
  final Value<int?> relatedId;
  final Value<String> description;
  final Value<double> amount;
  final Value<String> date;
  final Value<int?> cashTransactionId;
  const ExpensesCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.expenseType = const Value.absent(),
    this.relatedId = const Value.absent(),
    this.description = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.cashTransactionId = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    required String expenseType,
    this.relatedId = const Value.absent(),
    required String description,
    required double amount,
    required String date,
    this.cashTransactionId = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        expenseType = Value(expenseType),
        description = Value(description),
        amount = Value(amount),
        date = Value(date);
  static Insertable<Expense> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<String>? expenseType,
    Expression<int>? relatedId,
    Expression<String>? description,
    Expression<double>? amount,
    Expression<String>? date,
    Expression<int>? cashTransactionId,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (expenseType != null) 'expense_type': expenseType,
      if (relatedId != null) 'related_id': relatedId,
      if (description != null) 'description': description,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (cashTransactionId != null) 'cash_transaction_id': cashTransactionId,
    });
  }

  ExpensesCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<String>? expenseType,
      Value<int?>? relatedId,
      Value<String>? description,
      Value<double>? amount,
      Value<String>? date,
      Value<int?>? cashTransactionId}) {
    return ExpensesCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      expenseType: expenseType ?? this.expenseType,
      relatedId: relatedId ?? this.relatedId,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      cashTransactionId: cashTransactionId ?? this.cashTransactionId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expenseType.present) {
      map['expense_type'] = Variable<String>(expenseType.value);
    }
    if (relatedId.present) {
      map['related_id'] = Variable<int>(relatedId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<String>(date.value);
    }
    if (cashTransactionId.present) {
      map['cash_transaction_id'] = Variable<int>(cashTransactionId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('expenseType: $expenseType, ')
          ..write('relatedId: $relatedId, ')
          ..write('description: $description, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('cashTransactionId: $cashTransactionId')
          ..write(')'))
        .toString();
  }
}

class $CashTransactionsTable extends CashTransactions
    with TableInfo<$CashTransactionsTable, CashTransaction> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CashTransactionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _registerIdMeta =
      const VerificationMeta('registerId');
  @override
  late final GeneratedColumn<int> registerId = GeneratedColumn<int>(
      'register_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _transactionTypeMeta =
      const VerificationMeta('transactionType');
  @override
  late final GeneratedColumn<String> transactionType = GeneratedColumn<String>(
      'transaction_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _referenceTypeMeta =
      const VerificationMeta('referenceType');
  @override
  late final GeneratedColumn<String> referenceType = GeneratedColumn<String>(
      'reference_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _referenceIdMeta =
      const VerificationMeta('referenceId');
  @override
  late final GeneratedColumn<int> referenceId = GeneratedColumn<int>(
      'reference_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _transactionTimeMeta =
      const VerificationMeta('transactionTime');
  @override
  late final GeneratedColumn<String> transactionTime = GeneratedColumn<String>(
      'transaction_time', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdByMeta =
      const VerificationMeta('createdBy');
  @override
  late final GeneratedColumn<int> createdBy = GeneratedColumn<int>(
      'created_by', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        registerId,
        transactionType,
        amount,
        referenceType,
        referenceId,
        description,
        transactionTime,
        createdBy
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cash_transactions';
  @override
  VerificationContext validateIntegrity(Insertable<CashTransaction> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('register_id')) {
      context.handle(
          _registerIdMeta,
          registerId.isAcceptableOrUnknown(
              data['register_id']!, _registerIdMeta));
    }
    if (data.containsKey('transaction_type')) {
      context.handle(
          _transactionTypeMeta,
          transactionType.isAcceptableOrUnknown(
              data['transaction_type']!, _transactionTypeMeta));
    } else if (isInserting) {
      context.missing(_transactionTypeMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('reference_type')) {
      context.handle(
          _referenceTypeMeta,
          referenceType.isAcceptableOrUnknown(
              data['reference_type']!, _referenceTypeMeta));
    }
    if (data.containsKey('reference_id')) {
      context.handle(
          _referenceIdMeta,
          referenceId.isAcceptableOrUnknown(
              data['reference_id']!, _referenceIdMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('transaction_time')) {
      context.handle(
          _transactionTimeMeta,
          transactionTime.isAcceptableOrUnknown(
              data['transaction_time']!, _transactionTimeMeta));
    } else if (isInserting) {
      context.missing(_transactionTimeMeta);
    }
    if (data.containsKey('created_by')) {
      context.handle(_createdByMeta,
          createdBy.isAcceptableOrUnknown(data['created_by']!, _createdByMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CashTransaction map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CashTransaction(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      registerId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}register_id']),
      transactionType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}transaction_type'])!,
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      referenceType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reference_type']),
      referenceId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}reference_id']),
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description']),
      transactionTime: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}transaction_time'])!,
      createdBy: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_by']),
    );
  }

  @override
  $CashTransactionsTable createAlias(String alias) {
    return $CashTransactionsTable(attachedDatabase, alias);
  }
}

class CashTransaction extends DataClass implements Insertable<CashTransaction> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final int? registerId;
  final String transactionType;
  final double amount;
  final String? referenceType;
  final int? referenceId;
  final String? description;
  final String transactionTime;
  final int? createdBy;
  const CashTransaction(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      this.registerId,
      required this.transactionType,
      required this.amount,
      this.referenceType,
      this.referenceId,
      this.description,
      required this.transactionTime,
      this.createdBy});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || registerId != null) {
      map['register_id'] = Variable<int>(registerId);
    }
    map['transaction_type'] = Variable<String>(transactionType);
    map['amount'] = Variable<double>(amount);
    if (!nullToAbsent || referenceType != null) {
      map['reference_type'] = Variable<String>(referenceType);
    }
    if (!nullToAbsent || referenceId != null) {
      map['reference_id'] = Variable<int>(referenceId);
    }
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    map['transaction_time'] = Variable<String>(transactionTime);
    if (!nullToAbsent || createdBy != null) {
      map['created_by'] = Variable<int>(createdBy);
    }
    return map;
  }

  CashTransactionsCompanion toCompanion(bool nullToAbsent) {
    return CashTransactionsCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      registerId: registerId == null && nullToAbsent
          ? const Value.absent()
          : Value(registerId),
      transactionType: Value(transactionType),
      amount: Value(amount),
      referenceType: referenceType == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceType),
      referenceId: referenceId == null && nullToAbsent
          ? const Value.absent()
          : Value(referenceId),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      transactionTime: Value(transactionTime),
      createdBy: createdBy == null && nullToAbsent
          ? const Value.absent()
          : Value(createdBy),
    );
  }

  factory CashTransaction.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CashTransaction(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      registerId: serializer.fromJson<int?>(json['registerId']),
      transactionType: serializer.fromJson<String>(json['transactionType']),
      amount: serializer.fromJson<double>(json['amount']),
      referenceType: serializer.fromJson<String?>(json['referenceType']),
      referenceId: serializer.fromJson<int?>(json['referenceId']),
      description: serializer.fromJson<String?>(json['description']),
      transactionTime: serializer.fromJson<String>(json['transactionTime']),
      createdBy: serializer.fromJson<int?>(json['createdBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'registerId': serializer.toJson<int?>(registerId),
      'transactionType': serializer.toJson<String>(transactionType),
      'amount': serializer.toJson<double>(amount),
      'referenceType': serializer.toJson<String?>(referenceType),
      'referenceId': serializer.toJson<int?>(referenceId),
      'description': serializer.toJson<String?>(description),
      'transactionTime': serializer.toJson<String>(transactionTime),
      'createdBy': serializer.toJson<int?>(createdBy),
    };
  }

  CashTransaction copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          Value<int?> registerId = const Value.absent(),
          String? transactionType,
          double? amount,
          Value<String?> referenceType = const Value.absent(),
          Value<int?> referenceId = const Value.absent(),
          Value<String?> description = const Value.absent(),
          String? transactionTime,
          Value<int?> createdBy = const Value.absent()}) =>
      CashTransaction(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        registerId: registerId.present ? registerId.value : this.registerId,
        transactionType: transactionType ?? this.transactionType,
        amount: amount ?? this.amount,
        referenceType:
            referenceType.present ? referenceType.value : this.referenceType,
        referenceId: referenceId.present ? referenceId.value : this.referenceId,
        description: description.present ? description.value : this.description,
        transactionTime: transactionTime ?? this.transactionTime,
        createdBy: createdBy.present ? createdBy.value : this.createdBy,
      );
  CashTransaction copyWithCompanion(CashTransactionsCompanion data) {
    return CashTransaction(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      registerId:
          data.registerId.present ? data.registerId.value : this.registerId,
      transactionType: data.transactionType.present
          ? data.transactionType.value
          : this.transactionType,
      amount: data.amount.present ? data.amount.value : this.amount,
      referenceType: data.referenceType.present
          ? data.referenceType.value
          : this.referenceType,
      referenceId:
          data.referenceId.present ? data.referenceId.value : this.referenceId,
      description:
          data.description.present ? data.description.value : this.description,
      transactionTime: data.transactionTime.present
          ? data.transactionTime.value
          : this.transactionTime,
      createdBy: data.createdBy.present ? data.createdBy.value : this.createdBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CashTransaction(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('registerId: $registerId, ')
          ..write('transactionType: $transactionType, ')
          ..write('amount: $amount, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('description: $description, ')
          ..write('transactionTime: $transactionTime, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localUuid,
      serverId,
      createdAt,
      updatedAt,
      deletedAt,
      lastModified,
      version,
      origin,
      id,
      registerId,
      transactionType,
      amount,
      referenceType,
      referenceId,
      description,
      transactionTime,
      createdBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CashTransaction &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.registerId == this.registerId &&
          other.transactionType == this.transactionType &&
          other.amount == this.amount &&
          other.referenceType == this.referenceType &&
          other.referenceId == this.referenceId &&
          other.description == this.description &&
          other.transactionTime == this.transactionTime &&
          other.createdBy == this.createdBy);
}

class CashTransactionsCompanion extends UpdateCompanion<CashTransaction> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<int?> registerId;
  final Value<String> transactionType;
  final Value<double> amount;
  final Value<String?> referenceType;
  final Value<int?> referenceId;
  final Value<String?> description;
  final Value<String> transactionTime;
  final Value<int?> createdBy;
  const CashTransactionsCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.registerId = const Value.absent(),
    this.transactionType = const Value.absent(),
    this.amount = const Value.absent(),
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.description = const Value.absent(),
    this.transactionTime = const Value.absent(),
    this.createdBy = const Value.absent(),
  });
  CashTransactionsCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.registerId = const Value.absent(),
    required String transactionType,
    required double amount,
    this.referenceType = const Value.absent(),
    this.referenceId = const Value.absent(),
    this.description = const Value.absent(),
    required String transactionTime,
    this.createdBy = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        transactionType = Value(transactionType),
        amount = Value(amount),
        transactionTime = Value(transactionTime);
  static Insertable<CashTransaction> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<int>? registerId,
    Expression<String>? transactionType,
    Expression<double>? amount,
    Expression<String>? referenceType,
    Expression<int>? referenceId,
    Expression<String>? description,
    Expression<String>? transactionTime,
    Expression<int>? createdBy,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (registerId != null) 'register_id': registerId,
      if (transactionType != null) 'transaction_type': transactionType,
      if (amount != null) 'amount': amount,
      if (referenceType != null) 'reference_type': referenceType,
      if (referenceId != null) 'reference_id': referenceId,
      if (description != null) 'description': description,
      if (transactionTime != null) 'transaction_time': transactionTime,
      if (createdBy != null) 'created_by': createdBy,
    });
  }

  CashTransactionsCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<int?>? registerId,
      Value<String>? transactionType,
      Value<double>? amount,
      Value<String?>? referenceType,
      Value<int?>? referenceId,
      Value<String?>? description,
      Value<String>? transactionTime,
      Value<int?>? createdBy}) {
    return CashTransactionsCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      registerId: registerId ?? this.registerId,
      transactionType: transactionType ?? this.transactionType,
      amount: amount ?? this.amount,
      referenceType: referenceType ?? this.referenceType,
      referenceId: referenceId ?? this.referenceId,
      description: description ?? this.description,
      transactionTime: transactionTime ?? this.transactionTime,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (registerId.present) {
      map['register_id'] = Variable<int>(registerId.value);
    }
    if (transactionType.present) {
      map['transaction_type'] = Variable<String>(transactionType.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (referenceType.present) {
      map['reference_type'] = Variable<String>(referenceType.value);
    }
    if (referenceId.present) {
      map['reference_id'] = Variable<int>(referenceId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (transactionTime.present) {
      map['transaction_time'] = Variable<String>(transactionTime.value);
    }
    if (createdBy.present) {
      map['created_by'] = Variable<int>(createdBy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CashTransactionsCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('registerId: $registerId, ')
          ..write('transactionType: $transactionType, ')
          ..write('amount: $amount, ')
          ..write('referenceType: $referenceType, ')
          ..write('referenceId: $referenceId, ')
          ..write('description: $description, ')
          ..write('transactionTime: $transactionTime, ')
          ..write('createdBy: $createdBy')
          ..write(')'))
        .toString();
  }
}

class $PaymentsTable extends Payments with TableInfo<$PaymentsTable, Payment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PaymentsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<int> deletedAt = GeneratedColumn<int>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _lastModifiedMeta =
      const VerificationMeta('lastModified');
  @override
  late final GeneratedColumn<int> lastModified = GeneratedColumn<int>(
      'last_modified', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
      'origin', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('local'));
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverPaymentIdMeta =
      const VerificationMeta('serverPaymentId');
  @override
  late final GeneratedColumn<int> serverPaymentId = GeneratedColumn<int>(
      'server_payment_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _bookingLocalIdMeta =
      const VerificationMeta('bookingLocalId');
  @override
  late final GeneratedColumn<int> bookingLocalId = GeneratedColumn<int>(
      'booking_local_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES bookings (id)'));
  static const VerificationMeta _serverBookingIdMeta =
      const VerificationMeta('serverBookingId');
  @override
  late final GeneratedColumn<int> serverBookingId = GeneratedColumn<int>(
      'server_booking_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _roomNumberMeta =
      const VerificationMeta('roomNumber');
  @override
  late final GeneratedColumn<String> roomNumber = GeneratedColumn<String>(
      'room_number', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<double> amount = GeneratedColumn<double>(
      'amount', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _paymentDateMeta =
      const VerificationMeta('paymentDate');
  @override
  late final GeneratedColumn<String> paymentDate = GeneratedColumn<String>(
      'payment_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _paymentMethodMeta =
      const VerificationMeta('paymentMethod');
  @override
  late final GeneratedColumn<String> paymentMethod = GeneratedColumn<String>(
      'payment_method', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _revenueTypeMeta =
      const VerificationMeta('revenueType');
  @override
  late final GeneratedColumn<String> revenueType = GeneratedColumn<String>(
      'revenue_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cashTransactionLocalIdMeta =
      const VerificationMeta('cashTransactionLocalId');
  @override
  late final GeneratedColumn<int> cashTransactionLocalId = GeneratedColumn<int>(
      'cash_transaction_local_id', aliasedName, true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES cash_transactions (id)'));
  static const VerificationMeta _cashTransactionServerIdMeta =
      const VerificationMeta('cashTransactionServerId');
  @override
  late final GeneratedColumn<int> cashTransactionServerId =
      GeneratedColumn<int>('cash_transaction_server_id', aliasedName, true,
          type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localUuid,
        serverId,
        createdAt,
        updatedAt,
        deletedAt,
        lastModified,
        version,
        origin,
        id,
        serverPaymentId,
        bookingLocalId,
        serverBookingId,
        roomNumber,
        amount,
        paymentDate,
        notes,
        paymentMethod,
        revenueType,
        cashTransactionLocalId,
        cashTransactionServerId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'payments';
  @override
  VerificationContext validateIntegrity(Insertable<Payment> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('last_modified')) {
      context.handle(
          _lastModifiedMeta,
          lastModified.isAcceptableOrUnknown(
              data['last_modified']!, _lastModifiedMeta));
    } else if (isInserting) {
      context.missing(_lastModifiedMeta);
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    if (data.containsKey('origin')) {
      context.handle(_originMeta,
          origin.isAcceptableOrUnknown(data['origin']!, _originMeta));
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_payment_id')) {
      context.handle(
          _serverPaymentIdMeta,
          serverPaymentId.isAcceptableOrUnknown(
              data['server_payment_id']!, _serverPaymentIdMeta));
    }
    if (data.containsKey('booking_local_id')) {
      context.handle(
          _bookingLocalIdMeta,
          bookingLocalId.isAcceptableOrUnknown(
              data['booking_local_id']!, _bookingLocalIdMeta));
    }
    if (data.containsKey('server_booking_id')) {
      context.handle(
          _serverBookingIdMeta,
          serverBookingId.isAcceptableOrUnknown(
              data['server_booking_id']!, _serverBookingIdMeta));
    }
    if (data.containsKey('room_number')) {
      context.handle(
          _roomNumberMeta,
          roomNumber.isAcceptableOrUnknown(
              data['room_number']!, _roomNumberMeta));
    }
    if (data.containsKey('amount')) {
      context.handle(_amountMeta,
          amount.isAcceptableOrUnknown(data['amount']!, _amountMeta));
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('payment_date')) {
      context.handle(
          _paymentDateMeta,
          paymentDate.isAcceptableOrUnknown(
              data['payment_date']!, _paymentDateMeta));
    } else if (isInserting) {
      context.missing(_paymentDateMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('payment_method')) {
      context.handle(
          _paymentMethodMeta,
          paymentMethod.isAcceptableOrUnknown(
              data['payment_method']!, _paymentMethodMeta));
    } else if (isInserting) {
      context.missing(_paymentMethodMeta);
    }
    if (data.containsKey('revenue_type')) {
      context.handle(
          _revenueTypeMeta,
          revenueType.isAcceptableOrUnknown(
              data['revenue_type']!, _revenueTypeMeta));
    } else if (isInserting) {
      context.missing(_revenueTypeMeta);
    }
    if (data.containsKey('cash_transaction_local_id')) {
      context.handle(
          _cashTransactionLocalIdMeta,
          cashTransactionLocalId.isAcceptableOrUnknown(
              data['cash_transaction_local_id']!, _cashTransactionLocalIdMeta));
    }
    if (data.containsKey('cash_transaction_server_id')) {
      context.handle(
          _cashTransactionServerIdMeta,
          cashTransactionServerId.isAcceptableOrUnknown(
              data['cash_transaction_server_id']!,
              _cashTransactionServerIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Payment map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Payment(
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}deleted_at']),
      lastModified: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_modified'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
      origin: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}origin'])!,
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverPaymentId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_payment_id']),
      bookingLocalId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}booking_local_id']),
      serverBookingId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_booking_id']),
      roomNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}room_number']),
      amount: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}amount'])!,
      paymentDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_date'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      paymentMethod: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payment_method'])!,
      revenueType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}revenue_type'])!,
      cashTransactionLocalId: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}cash_transaction_local_id']),
      cashTransactionServerId: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}cash_transaction_server_id']),
    );
  }

  @override
  $PaymentsTable createAlias(String alias) {
    return $PaymentsTable(attachedDatabase, alias);
  }
}

class Payment extends DataClass implements Insertable<Payment> {
  final String localUuid;
  final int? serverId;
  final int createdAt;
  final int updatedAt;
  final int? deletedAt;
  final int lastModified;
  final int version;
  final String origin;
  final int id;
  final int? serverPaymentId;
  final int? bookingLocalId;
  final int? serverBookingId;
  final String? roomNumber;
  final double amount;
  final String paymentDate;
  final String? notes;
  final String paymentMethod;
  final String revenueType;
  final int? cashTransactionLocalId;
  final int? cashTransactionServerId;
  const Payment(
      {required this.localUuid,
      this.serverId,
      required this.createdAt,
      required this.updatedAt,
      this.deletedAt,
      required this.lastModified,
      required this.version,
      required this.origin,
      required this.id,
      this.serverPaymentId,
      this.bookingLocalId,
      this.serverBookingId,
      this.roomNumber,
      required this.amount,
      required this.paymentDate,
      this.notes,
      required this.paymentMethod,
      required this.revenueType,
      this.cashTransactionLocalId,
      this.cashTransactionServerId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<int>(deletedAt);
    }
    map['last_modified'] = Variable<int>(lastModified);
    map['version'] = Variable<int>(version);
    map['origin'] = Variable<String>(origin);
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || serverPaymentId != null) {
      map['server_payment_id'] = Variable<int>(serverPaymentId);
    }
    if (!nullToAbsent || bookingLocalId != null) {
      map['booking_local_id'] = Variable<int>(bookingLocalId);
    }
    if (!nullToAbsent || serverBookingId != null) {
      map['server_booking_id'] = Variable<int>(serverBookingId);
    }
    if (!nullToAbsent || roomNumber != null) {
      map['room_number'] = Variable<String>(roomNumber);
    }
    map['amount'] = Variable<double>(amount);
    map['payment_date'] = Variable<String>(paymentDate);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['payment_method'] = Variable<String>(paymentMethod);
    map['revenue_type'] = Variable<String>(revenueType);
    if (!nullToAbsent || cashTransactionLocalId != null) {
      map['cash_transaction_local_id'] = Variable<int>(cashTransactionLocalId);
    }
    if (!nullToAbsent || cashTransactionServerId != null) {
      map['cash_transaction_server_id'] =
          Variable<int>(cashTransactionServerId);
    }
    return map;
  }

  PaymentsCompanion toCompanion(bool nullToAbsent) {
    return PaymentsCompanion(
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      lastModified: Value(lastModified),
      version: Value(version),
      origin: Value(origin),
      id: Value(id),
      serverPaymentId: serverPaymentId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverPaymentId),
      bookingLocalId: bookingLocalId == null && nullToAbsent
          ? const Value.absent()
          : Value(bookingLocalId),
      serverBookingId: serverBookingId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverBookingId),
      roomNumber: roomNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(roomNumber),
      amount: Value(amount),
      paymentDate: Value(paymentDate),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      paymentMethod: Value(paymentMethod),
      revenueType: Value(revenueType),
      cashTransactionLocalId: cashTransactionLocalId == null && nullToAbsent
          ? const Value.absent()
          : Value(cashTransactionLocalId),
      cashTransactionServerId: cashTransactionServerId == null && nullToAbsent
          ? const Value.absent()
          : Value(cashTransactionServerId),
    );
  }

  factory Payment.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Payment(
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deletedAt: serializer.fromJson<int?>(json['deletedAt']),
      lastModified: serializer.fromJson<int>(json['lastModified']),
      version: serializer.fromJson<int>(json['version']),
      origin: serializer.fromJson<String>(json['origin']),
      id: serializer.fromJson<int>(json['id']),
      serverPaymentId: serializer.fromJson<int?>(json['serverPaymentId']),
      bookingLocalId: serializer.fromJson<int?>(json['bookingLocalId']),
      serverBookingId: serializer.fromJson<int?>(json['serverBookingId']),
      roomNumber: serializer.fromJson<String?>(json['roomNumber']),
      amount: serializer.fromJson<double>(json['amount']),
      paymentDate: serializer.fromJson<String>(json['paymentDate']),
      notes: serializer.fromJson<String?>(json['notes']),
      paymentMethod: serializer.fromJson<String>(json['paymentMethod']),
      revenueType: serializer.fromJson<String>(json['revenueType']),
      cashTransactionLocalId:
          serializer.fromJson<int?>(json['cashTransactionLocalId']),
      cashTransactionServerId:
          serializer.fromJson<int?>(json['cashTransactionServerId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deletedAt': serializer.toJson<int?>(deletedAt),
      'lastModified': serializer.toJson<int>(lastModified),
      'version': serializer.toJson<int>(version),
      'origin': serializer.toJson<String>(origin),
      'id': serializer.toJson<int>(id),
      'serverPaymentId': serializer.toJson<int?>(serverPaymentId),
      'bookingLocalId': serializer.toJson<int?>(bookingLocalId),
      'serverBookingId': serializer.toJson<int?>(serverBookingId),
      'roomNumber': serializer.toJson<String?>(roomNumber),
      'amount': serializer.toJson<double>(amount),
      'paymentDate': serializer.toJson<String>(paymentDate),
      'notes': serializer.toJson<String?>(notes),
      'paymentMethod': serializer.toJson<String>(paymentMethod),
      'revenueType': serializer.toJson<String>(revenueType),
      'cashTransactionLocalId': serializer.toJson<int?>(cashTransactionLocalId),
      'cashTransactionServerId':
          serializer.toJson<int?>(cashTransactionServerId),
    };
  }

  Payment copyWith(
          {String? localUuid,
          Value<int?> serverId = const Value.absent(),
          int? createdAt,
          int? updatedAt,
          Value<int?> deletedAt = const Value.absent(),
          int? lastModified,
          int? version,
          String? origin,
          int? id,
          Value<int?> serverPaymentId = const Value.absent(),
          Value<int?> bookingLocalId = const Value.absent(),
          Value<int?> serverBookingId = const Value.absent(),
          Value<String?> roomNumber = const Value.absent(),
          double? amount,
          String? paymentDate,
          Value<String?> notes = const Value.absent(),
          String? paymentMethod,
          String? revenueType,
          Value<int?> cashTransactionLocalId = const Value.absent(),
          Value<int?> cashTransactionServerId = const Value.absent()}) =>
      Payment(
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        lastModified: lastModified ?? this.lastModified,
        version: version ?? this.version,
        origin: origin ?? this.origin,
        id: id ?? this.id,
        serverPaymentId: serverPaymentId.present
            ? serverPaymentId.value
            : this.serverPaymentId,
        bookingLocalId:
            bookingLocalId.present ? bookingLocalId.value : this.bookingLocalId,
        serverBookingId: serverBookingId.present
            ? serverBookingId.value
            : this.serverBookingId,
        roomNumber: roomNumber.present ? roomNumber.value : this.roomNumber,
        amount: amount ?? this.amount,
        paymentDate: paymentDate ?? this.paymentDate,
        notes: notes.present ? notes.value : this.notes,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        revenueType: revenueType ?? this.revenueType,
        cashTransactionLocalId: cashTransactionLocalId.present
            ? cashTransactionLocalId.value
            : this.cashTransactionLocalId,
        cashTransactionServerId: cashTransactionServerId.present
            ? cashTransactionServerId.value
            : this.cashTransactionServerId,
      );
  Payment copyWithCompanion(PaymentsCompanion data) {
    return Payment(
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      lastModified: data.lastModified.present
          ? data.lastModified.value
          : this.lastModified,
      version: data.version.present ? data.version.value : this.version,
      origin: data.origin.present ? data.origin.value : this.origin,
      id: data.id.present ? data.id.value : this.id,
      serverPaymentId: data.serverPaymentId.present
          ? data.serverPaymentId.value
          : this.serverPaymentId,
      bookingLocalId: data.bookingLocalId.present
          ? data.bookingLocalId.value
          : this.bookingLocalId,
      serverBookingId: data.serverBookingId.present
          ? data.serverBookingId.value
          : this.serverBookingId,
      roomNumber:
          data.roomNumber.present ? data.roomNumber.value : this.roomNumber,
      amount: data.amount.present ? data.amount.value : this.amount,
      paymentDate:
          data.paymentDate.present ? data.paymentDate.value : this.paymentDate,
      notes: data.notes.present ? data.notes.value : this.notes,
      paymentMethod: data.paymentMethod.present
          ? data.paymentMethod.value
          : this.paymentMethod,
      revenueType:
          data.revenueType.present ? data.revenueType.value : this.revenueType,
      cashTransactionLocalId: data.cashTransactionLocalId.present
          ? data.cashTransactionLocalId.value
          : this.cashTransactionLocalId,
      cashTransactionServerId: data.cashTransactionServerId.present
          ? data.cashTransactionServerId.value
          : this.cashTransactionServerId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Payment(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('serverPaymentId: $serverPaymentId, ')
          ..write('bookingLocalId: $bookingLocalId, ')
          ..write('serverBookingId: $serverBookingId, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('amount: $amount, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('revenueType: $revenueType, ')
          ..write('cashTransactionLocalId: $cashTransactionLocalId, ')
          ..write('cashTransactionServerId: $cashTransactionServerId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      localUuid,
      serverId,
      createdAt,
      updatedAt,
      deletedAt,
      lastModified,
      version,
      origin,
      id,
      serverPaymentId,
      bookingLocalId,
      serverBookingId,
      roomNumber,
      amount,
      paymentDate,
      notes,
      paymentMethod,
      revenueType,
      cashTransactionLocalId,
      cashTransactionServerId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Payment &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deletedAt == this.deletedAt &&
          other.lastModified == this.lastModified &&
          other.version == this.version &&
          other.origin == this.origin &&
          other.id == this.id &&
          other.serverPaymentId == this.serverPaymentId &&
          other.bookingLocalId == this.bookingLocalId &&
          other.serverBookingId == this.serverBookingId &&
          other.roomNumber == this.roomNumber &&
          other.amount == this.amount &&
          other.paymentDate == this.paymentDate &&
          other.notes == this.notes &&
          other.paymentMethod == this.paymentMethod &&
          other.revenueType == this.revenueType &&
          other.cashTransactionLocalId == this.cashTransactionLocalId &&
          other.cashTransactionServerId == this.cashTransactionServerId);
}

class PaymentsCompanion extends UpdateCompanion<Payment> {
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int?> deletedAt;
  final Value<int> lastModified;
  final Value<int> version;
  final Value<String> origin;
  final Value<int> id;
  final Value<int?> serverPaymentId;
  final Value<int?> bookingLocalId;
  final Value<int?> serverBookingId;
  final Value<String?> roomNumber;
  final Value<double> amount;
  final Value<String> paymentDate;
  final Value<String?> notes;
  final Value<String> paymentMethod;
  final Value<String> revenueType;
  final Value<int?> cashTransactionLocalId;
  final Value<int?> cashTransactionServerId;
  const PaymentsCompanion({
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.lastModified = const Value.absent(),
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.serverPaymentId = const Value.absent(),
    this.bookingLocalId = const Value.absent(),
    this.serverBookingId = const Value.absent(),
    this.roomNumber = const Value.absent(),
    this.amount = const Value.absent(),
    this.paymentDate = const Value.absent(),
    this.notes = const Value.absent(),
    this.paymentMethod = const Value.absent(),
    this.revenueType = const Value.absent(),
    this.cashTransactionLocalId = const Value.absent(),
    this.cashTransactionServerId = const Value.absent(),
  });
  PaymentsCompanion.insert({
    required String localUuid,
    this.serverId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.deletedAt = const Value.absent(),
    required int lastModified,
    this.version = const Value.absent(),
    this.origin = const Value.absent(),
    this.id = const Value.absent(),
    this.serverPaymentId = const Value.absent(),
    this.bookingLocalId = const Value.absent(),
    this.serverBookingId = const Value.absent(),
    this.roomNumber = const Value.absent(),
    required double amount,
    required String paymentDate,
    this.notes = const Value.absent(),
    required String paymentMethod,
    required String revenueType,
    this.cashTransactionLocalId = const Value.absent(),
    this.cashTransactionServerId = const Value.absent(),
  })  : localUuid = Value(localUuid),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt),
        lastModified = Value(lastModified),
        amount = Value(amount),
        paymentDate = Value(paymentDate),
        paymentMethod = Value(paymentMethod),
        revenueType = Value(revenueType);
  static Insertable<Payment> custom({
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? deletedAt,
    Expression<int>? lastModified,
    Expression<int>? version,
    Expression<String>? origin,
    Expression<int>? id,
    Expression<int>? serverPaymentId,
    Expression<int>? bookingLocalId,
    Expression<int>? serverBookingId,
    Expression<String>? roomNumber,
    Expression<double>? amount,
    Expression<String>? paymentDate,
    Expression<String>? notes,
    Expression<String>? paymentMethod,
    Expression<String>? revenueType,
    Expression<int>? cashTransactionLocalId,
    Expression<int>? cashTransactionServerId,
  }) {
    return RawValuesInsertable({
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (lastModified != null) 'last_modified': lastModified,
      if (version != null) 'version': version,
      if (origin != null) 'origin': origin,
      if (id != null) 'id': id,
      if (serverPaymentId != null) 'server_payment_id': serverPaymentId,
      if (bookingLocalId != null) 'booking_local_id': bookingLocalId,
      if (serverBookingId != null) 'server_booking_id': serverBookingId,
      if (roomNumber != null) 'room_number': roomNumber,
      if (amount != null) 'amount': amount,
      if (paymentDate != null) 'payment_date': paymentDate,
      if (notes != null) 'notes': notes,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (revenueType != null) 'revenue_type': revenueType,
      if (cashTransactionLocalId != null)
        'cash_transaction_local_id': cashTransactionLocalId,
      if (cashTransactionServerId != null)
        'cash_transaction_server_id': cashTransactionServerId,
    });
  }

  PaymentsCompanion copyWith(
      {Value<String>? localUuid,
      Value<int?>? serverId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int?>? deletedAt,
      Value<int>? lastModified,
      Value<int>? version,
      Value<String>? origin,
      Value<int>? id,
      Value<int?>? serverPaymentId,
      Value<int?>? bookingLocalId,
      Value<int?>? serverBookingId,
      Value<String?>? roomNumber,
      Value<double>? amount,
      Value<String>? paymentDate,
      Value<String?>? notes,
      Value<String>? paymentMethod,
      Value<String>? revenueType,
      Value<int?>? cashTransactionLocalId,
      Value<int?>? cashTransactionServerId}) {
    return PaymentsCompanion(
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      lastModified: lastModified ?? this.lastModified,
      version: version ?? this.version,
      origin: origin ?? this.origin,
      id: id ?? this.id,
      serverPaymentId: serverPaymentId ?? this.serverPaymentId,
      bookingLocalId: bookingLocalId ?? this.bookingLocalId,
      serverBookingId: serverBookingId ?? this.serverBookingId,
      roomNumber: roomNumber ?? this.roomNumber,
      amount: amount ?? this.amount,
      paymentDate: paymentDate ?? this.paymentDate,
      notes: notes ?? this.notes,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      revenueType: revenueType ?? this.revenueType,
      cashTransactionLocalId:
          cashTransactionLocalId ?? this.cashTransactionLocalId,
      cashTransactionServerId:
          cashTransactionServerId ?? this.cashTransactionServerId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<int>(deletedAt.value);
    }
    if (lastModified.present) {
      map['last_modified'] = Variable<int>(lastModified.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverPaymentId.present) {
      map['server_payment_id'] = Variable<int>(serverPaymentId.value);
    }
    if (bookingLocalId.present) {
      map['booking_local_id'] = Variable<int>(bookingLocalId.value);
    }
    if (serverBookingId.present) {
      map['server_booking_id'] = Variable<int>(serverBookingId.value);
    }
    if (roomNumber.present) {
      map['room_number'] = Variable<String>(roomNumber.value);
    }
    if (amount.present) {
      map['amount'] = Variable<double>(amount.value);
    }
    if (paymentDate.present) {
      map['payment_date'] = Variable<String>(paymentDate.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (paymentMethod.present) {
      map['payment_method'] = Variable<String>(paymentMethod.value);
    }
    if (revenueType.present) {
      map['revenue_type'] = Variable<String>(revenueType.value);
    }
    if (cashTransactionLocalId.present) {
      map['cash_transaction_local_id'] =
          Variable<int>(cashTransactionLocalId.value);
    }
    if (cashTransactionServerId.present) {
      map['cash_transaction_server_id'] =
          Variable<int>(cashTransactionServerId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PaymentsCompanion(')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('lastModified: $lastModified, ')
          ..write('version: $version, ')
          ..write('origin: $origin, ')
          ..write('id: $id, ')
          ..write('serverPaymentId: $serverPaymentId, ')
          ..write('bookingLocalId: $bookingLocalId, ')
          ..write('serverBookingId: $serverBookingId, ')
          ..write('roomNumber: $roomNumber, ')
          ..write('amount: $amount, ')
          ..write('paymentDate: $paymentDate, ')
          ..write('notes: $notes, ')
          ..write('paymentMethod: $paymentMethod, ')
          ..write('revenueType: $revenueType, ')
          ..write('cashTransactionLocalId: $cashTransactionLocalId, ')
          ..write('cashTransactionServerId: $cashTransactionServerId')
          ..write(')'))
        .toString();
  }
}

class $OutboxTable extends Outbox with TableInfo<$OutboxTable, OutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
      'entity', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
      'op', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _localUuidMeta =
      const VerificationMeta('localUuid');
  @override
  late final GeneratedColumn<String> localUuid = GeneratedColumn<String>(
      'local_uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<int> serverId = GeneratedColumn<int>(
      'server_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _payloadMeta =
      const VerificationMeta('payload');
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
      'payload', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _clientTsMeta =
      const VerificationMeta('clientTs');
  @override
  late final GeneratedColumn<int> clientTs = GeneratedColumn<int>(
      'client_ts', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        entity,
        op,
        localUuid,
        serverId,
        payload,
        clientTs,
        attempts,
        lastError
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbox';
  @override
  VerificationContext validateIntegrity(Insertable<OutboxData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('entity')) {
      context.handle(_entityMeta,
          entity.isAcceptableOrUnknown(data['entity']!, _entityMeta));
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('local_uuid')) {
      context.handle(_localUuidMeta,
          localUuid.isAcceptableOrUnknown(data['local_uuid']!, _localUuidMeta));
    } else if (isInserting) {
      context.missing(_localUuidMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('payload')) {
      context.handle(_payloadMeta,
          payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta));
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('client_ts')) {
      context.handle(_clientTsMeta,
          clientTs.isAcceptableOrUnknown(data['client_ts']!, _clientTsMeta));
    } else if (isInserting) {
      context.missing(_clientTsMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboxData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      entity: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entity'])!,
      op: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}op'])!,
      localUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_uuid'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}server_id']),
      payload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}payload'])!,
      clientTs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}client_ts'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
    );
  }

  @override
  $OutboxTable createAlias(String alias) {
    return $OutboxTable(attachedDatabase, alias);
  }
}

class OutboxData extends DataClass implements Insertable<OutboxData> {
  final int id;
  final String entity;
  final String op;
  final String localUuid;
  final int? serverId;
  final String payload;
  final int clientTs;
  final int attempts;
  final String? lastError;
  const OutboxData(
      {required this.id,
      required this.entity,
      required this.op,
      required this.localUuid,
      this.serverId,
      required this.payload,
      required this.clientTs,
      required this.attempts,
      this.lastError});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['entity'] = Variable<String>(entity);
    map['op'] = Variable<String>(op);
    map['local_uuid'] = Variable<String>(localUuid);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<int>(serverId);
    }
    map['payload'] = Variable<String>(payload);
    map['client_ts'] = Variable<int>(clientTs);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  OutboxCompanion toCompanion(bool nullToAbsent) {
    return OutboxCompanion(
      id: Value(id),
      entity: Value(entity),
      op: Value(op),
      localUuid: Value(localUuid),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      payload: Value(payload),
      clientTs: Value(clientTs),
      attempts: Value(attempts),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory OutboxData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboxData(
      id: serializer.fromJson<int>(json['id']),
      entity: serializer.fromJson<String>(json['entity']),
      op: serializer.fromJson<String>(json['op']),
      localUuid: serializer.fromJson<String>(json['localUuid']),
      serverId: serializer.fromJson<int?>(json['serverId']),
      payload: serializer.fromJson<String>(json['payload']),
      clientTs: serializer.fromJson<int>(json['clientTs']),
      attempts: serializer.fromJson<int>(json['attempts']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'entity': serializer.toJson<String>(entity),
      'op': serializer.toJson<String>(op),
      'localUuid': serializer.toJson<String>(localUuid),
      'serverId': serializer.toJson<int?>(serverId),
      'payload': serializer.toJson<String>(payload),
      'clientTs': serializer.toJson<int>(clientTs),
      'attempts': serializer.toJson<int>(attempts),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  OutboxData copyWith(
          {int? id,
          String? entity,
          String? op,
          String? localUuid,
          Value<int?> serverId = const Value.absent(),
          String? payload,
          int? clientTs,
          int? attempts,
          Value<String?> lastError = const Value.absent()}) =>
      OutboxData(
        id: id ?? this.id,
        entity: entity ?? this.entity,
        op: op ?? this.op,
        localUuid: localUuid ?? this.localUuid,
        serverId: serverId.present ? serverId.value : this.serverId,
        payload: payload ?? this.payload,
        clientTs: clientTs ?? this.clientTs,
        attempts: attempts ?? this.attempts,
        lastError: lastError.present ? lastError.value : this.lastError,
      );
  OutboxData copyWithCompanion(OutboxCompanion data) {
    return OutboxData(
      id: data.id.present ? data.id.value : this.id,
      entity: data.entity.present ? data.entity.value : this.entity,
      op: data.op.present ? data.op.value : this.op,
      localUuid: data.localUuid.present ? data.localUuid.value : this.localUuid,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      payload: data.payload.present ? data.payload.value : this.payload,
      clientTs: data.clientTs.present ? data.clientTs.value : this.clientTs,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboxData(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('op: $op, ')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('payload: $payload, ')
          ..write('clientTs: $clientTs, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, entity, op, localUuid, serverId, payload,
      clientTs, attempts, lastError);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboxData &&
          other.id == this.id &&
          other.entity == this.entity &&
          other.op == this.op &&
          other.localUuid == this.localUuid &&
          other.serverId == this.serverId &&
          other.payload == this.payload &&
          other.clientTs == this.clientTs &&
          other.attempts == this.attempts &&
          other.lastError == this.lastError);
}

class OutboxCompanion extends UpdateCompanion<OutboxData> {
  final Value<int> id;
  final Value<String> entity;
  final Value<String> op;
  final Value<String> localUuid;
  final Value<int?> serverId;
  final Value<String> payload;
  final Value<int> clientTs;
  final Value<int> attempts;
  final Value<String?> lastError;
  const OutboxCompanion({
    this.id = const Value.absent(),
    this.entity = const Value.absent(),
    this.op = const Value.absent(),
    this.localUuid = const Value.absent(),
    this.serverId = const Value.absent(),
    this.payload = const Value.absent(),
    this.clientTs = const Value.absent(),
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  });
  OutboxCompanion.insert({
    this.id = const Value.absent(),
    required String entity,
    required String op,
    required String localUuid,
    this.serverId = const Value.absent(),
    required String payload,
    required int clientTs,
    this.attempts = const Value.absent(),
    this.lastError = const Value.absent(),
  })  : entity = Value(entity),
        op = Value(op),
        localUuid = Value(localUuid),
        payload = Value(payload),
        clientTs = Value(clientTs);
  static Insertable<OutboxData> custom({
    Expression<int>? id,
    Expression<String>? entity,
    Expression<String>? op,
    Expression<String>? localUuid,
    Expression<int>? serverId,
    Expression<String>? payload,
    Expression<int>? clientTs,
    Expression<int>? attempts,
    Expression<String>? lastError,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (entity != null) 'entity': entity,
      if (op != null) 'op': op,
      if (localUuid != null) 'local_uuid': localUuid,
      if (serverId != null) 'server_id': serverId,
      if (payload != null) 'payload': payload,
      if (clientTs != null) 'client_ts': clientTs,
      if (attempts != null) 'attempts': attempts,
      if (lastError != null) 'last_error': lastError,
    });
  }

  OutboxCompanion copyWith(
      {Value<int>? id,
      Value<String>? entity,
      Value<String>? op,
      Value<String>? localUuid,
      Value<int?>? serverId,
      Value<String>? payload,
      Value<int>? clientTs,
      Value<int>? attempts,
      Value<String?>? lastError}) {
    return OutboxCompanion(
      id: id ?? this.id,
      entity: entity ?? this.entity,
      op: op ?? this.op,
      localUuid: localUuid ?? this.localUuid,
      serverId: serverId ?? this.serverId,
      payload: payload ?? this.payload,
      clientTs: clientTs ?? this.clientTs,
      attempts: attempts ?? this.attempts,
      lastError: lastError ?? this.lastError,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (localUuid.present) {
      map['local_uuid'] = Variable<String>(localUuid.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<int>(serverId.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (clientTs.present) {
      map['client_ts'] = Variable<int>(clientTs.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboxCompanion(')
          ..write('id: $id, ')
          ..write('entity: $entity, ')
          ..write('op: $op, ')
          ..write('localUuid: $localUuid, ')
          ..write('serverId: $serverId, ')
          ..write('payload: $payload, ')
          ..write('clientTs: $clientTs, ')
          ..write('attempts: $attempts, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }
}

class $SyncStateTable extends SyncState
    with TableInfo<$SyncStateTable, SyncStateData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStateTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _lastServerTsMeta =
      const VerificationMeta('lastServerTs');
  @override
  late final GeneratedColumn<int> lastServerTs = GeneratedColumn<int>(
      'last_server_ts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPullTsMeta =
      const VerificationMeta('lastPullTs');
  @override
  late final GeneratedColumn<int> lastPullTs = GeneratedColumn<int>(
      'last_pull_ts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPushTsMeta =
      const VerificationMeta('lastPushTs');
  @override
  late final GeneratedColumn<int> lastPushTs = GeneratedColumn<int>(
      'last_push_ts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isSyncingMeta =
      const VerificationMeta('isSyncing');
  @override
  late final GeneratedColumn<int> isSyncing = GeneratedColumn<int>(
      'is_syncing', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _versionMeta =
      const VerificationMeta('version');
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
      'version', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  @override
  List<GeneratedColumn> get $columns =>
      [id, lastServerTs, lastPullTs, lastPushTs, isSyncing, version];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_state';
  @override
  VerificationContext validateIntegrity(Insertable<SyncStateData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_server_ts')) {
      context.handle(
          _lastServerTsMeta,
          lastServerTs.isAcceptableOrUnknown(
              data['last_server_ts']!, _lastServerTsMeta));
    }
    if (data.containsKey('last_pull_ts')) {
      context.handle(
          _lastPullTsMeta,
          lastPullTs.isAcceptableOrUnknown(
              data['last_pull_ts']!, _lastPullTsMeta));
    }
    if (data.containsKey('last_push_ts')) {
      context.handle(
          _lastPushTsMeta,
          lastPushTs.isAcceptableOrUnknown(
              data['last_push_ts']!, _lastPushTsMeta));
    }
    if (data.containsKey('is_syncing')) {
      context.handle(_isSyncingMeta,
          isSyncing.isAcceptableOrUnknown(data['is_syncing']!, _isSyncingMeta));
    }
    if (data.containsKey('version')) {
      context.handle(_versionMeta,
          version.isAcceptableOrUnknown(data['version']!, _versionMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SyncStateData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncStateData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      lastServerTs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_server_ts'])!,
      lastPullTs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_pull_ts'])!,
      lastPushTs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_push_ts'])!,
      isSyncing: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}is_syncing'])!,
      version: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}version'])!,
    );
  }

  @override
  $SyncStateTable createAlias(String alias) {
    return $SyncStateTable(attachedDatabase, alias);
  }
}

class SyncStateData extends DataClass implements Insertable<SyncStateData> {
  final int id;
  final int lastServerTs;
  final int lastPullTs;
  final int lastPushTs;
  final int isSyncing;
  final int version;
  const SyncStateData(
      {required this.id,
      required this.lastServerTs,
      required this.lastPullTs,
      required this.lastPushTs,
      required this.isSyncing,
      required this.version});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['last_server_ts'] = Variable<int>(lastServerTs);
    map['last_pull_ts'] = Variable<int>(lastPullTs);
    map['last_push_ts'] = Variable<int>(lastPushTs);
    map['is_syncing'] = Variable<int>(isSyncing);
    map['version'] = Variable<int>(version);
    return map;
  }

  SyncStateCompanion toCompanion(bool nullToAbsent) {
    return SyncStateCompanion(
      id: Value(id),
      lastServerTs: Value(lastServerTs),
      lastPullTs: Value(lastPullTs),
      lastPushTs: Value(lastPushTs),
      isSyncing: Value(isSyncing),
      version: Value(version),
    );
  }

  factory SyncStateData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncStateData(
      id: serializer.fromJson<int>(json['id']),
      lastServerTs: serializer.fromJson<int>(json['lastServerTs']),
      lastPullTs: serializer.fromJson<int>(json['lastPullTs']),
      lastPushTs: serializer.fromJson<int>(json['lastPushTs']),
      isSyncing: serializer.fromJson<int>(json['isSyncing']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastServerTs': serializer.toJson<int>(lastServerTs),
      'lastPullTs': serializer.toJson<int>(lastPullTs),
      'lastPushTs': serializer.toJson<int>(lastPushTs),
      'isSyncing': serializer.toJson<int>(isSyncing),
      'version': serializer.toJson<int>(version),
    };
  }

  SyncStateData copyWith(
          {int? id,
          int? lastServerTs,
          int? lastPullTs,
          int? lastPushTs,
          int? isSyncing,
          int? version}) =>
      SyncStateData(
        id: id ?? this.id,
        lastServerTs: lastServerTs ?? this.lastServerTs,
        lastPullTs: lastPullTs ?? this.lastPullTs,
        lastPushTs: lastPushTs ?? this.lastPushTs,
        isSyncing: isSyncing ?? this.isSyncing,
        version: version ?? this.version,
      );
  SyncStateData copyWithCompanion(SyncStateCompanion data) {
    return SyncStateData(
      id: data.id.present ? data.id.value : this.id,
      lastServerTs: data.lastServerTs.present
          ? data.lastServerTs.value
          : this.lastServerTs,
      lastPullTs:
          data.lastPullTs.present ? data.lastPullTs.value : this.lastPullTs,
      lastPushTs:
          data.lastPushTs.present ? data.lastPushTs.value : this.lastPushTs,
      isSyncing: data.isSyncing.present ? data.isSyncing.value : this.isSyncing,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateData(')
          ..write('id: $id, ')
          ..write('lastServerTs: $lastServerTs, ')
          ..write('lastPullTs: $lastPullTs, ')
          ..write('lastPushTs: $lastPushTs, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, lastServerTs, lastPullTs, lastPushTs, isSyncing, version);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncStateData &&
          other.id == this.id &&
          other.lastServerTs == this.lastServerTs &&
          other.lastPullTs == this.lastPullTs &&
          other.lastPushTs == this.lastPushTs &&
          other.isSyncing == this.isSyncing &&
          other.version == this.version);
}

class SyncStateCompanion extends UpdateCompanion<SyncStateData> {
  final Value<int> id;
  final Value<int> lastServerTs;
  final Value<int> lastPullTs;
  final Value<int> lastPushTs;
  final Value<int> isSyncing;
  final Value<int> version;
  const SyncStateCompanion({
    this.id = const Value.absent(),
    this.lastServerTs = const Value.absent(),
    this.lastPullTs = const Value.absent(),
    this.lastPushTs = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.version = const Value.absent(),
  });
  SyncStateCompanion.insert({
    this.id = const Value.absent(),
    this.lastServerTs = const Value.absent(),
    this.lastPullTs = const Value.absent(),
    this.lastPushTs = const Value.absent(),
    this.isSyncing = const Value.absent(),
    this.version = const Value.absent(),
  });
  static Insertable<SyncStateData> custom({
    Expression<int>? id,
    Expression<int>? lastServerTs,
    Expression<int>? lastPullTs,
    Expression<int>? lastPushTs,
    Expression<int>? isSyncing,
    Expression<int>? version,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastServerTs != null) 'last_server_ts': lastServerTs,
      if (lastPullTs != null) 'last_pull_ts': lastPullTs,
      if (lastPushTs != null) 'last_push_ts': lastPushTs,
      if (isSyncing != null) 'is_syncing': isSyncing,
      if (version != null) 'version': version,
    });
  }

  SyncStateCompanion copyWith(
      {Value<int>? id,
      Value<int>? lastServerTs,
      Value<int>? lastPullTs,
      Value<int>? lastPushTs,
      Value<int>? isSyncing,
      Value<int>? version}) {
    return SyncStateCompanion(
      id: id ?? this.id,
      lastServerTs: lastServerTs ?? this.lastServerTs,
      lastPullTs: lastPullTs ?? this.lastPullTs,
      lastPushTs: lastPushTs ?? this.lastPushTs,
      isSyncing: isSyncing ?? this.isSyncing,
      version: version ?? this.version,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastServerTs.present) {
      map['last_server_ts'] = Variable<int>(lastServerTs.value);
    }
    if (lastPullTs.present) {
      map['last_pull_ts'] = Variable<int>(lastPullTs.value);
    }
    if (lastPushTs.present) {
      map['last_push_ts'] = Variable<int>(lastPushTs.value);
    }
    if (isSyncing.present) {
      map['is_syncing'] = Variable<int>(isSyncing.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStateCompanion(')
          ..write('id: $id, ')
          ..write('lastServerTs: $lastServerTs, ')
          ..write('lastPullTs: $lastPullTs, ')
          ..write('lastPushTs: $lastPushTs, ')
          ..write('isSyncing: $isSyncing, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $BookingsTable bookings = $BookingsTable(this);
  late final $BookingNotesTable bookingNotes = $BookingNotesTable(this);
  late final $EmployeesTable employees = $EmployeesTable(this);
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $CashTransactionsTable cashTransactions =
      $CashTransactionsTable(this);
  late final $PaymentsTable payments = $PaymentsTable(this);
  late final $OutboxTable outbox = $OutboxTable(this);
  late final $SyncStateTable syncState = $SyncStateTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        rooms,
        bookings,
        bookingNotes,
        employees,
        expenses,
        cashTransactions,
        payments,
        outbox,
        syncState
      ];
}

typedef $$RoomsTableCreateCompanionBuilder = RoomsCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  required String roomNumber,
  required String type,
  required double price,
  required String status,
  Value<String?> imageUrl,
  Value<int> rowid,
});
typedef $$RoomsTableUpdateCompanionBuilder = RoomsCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<String> roomNumber,
  Value<String> type,
  Value<double> price,
  Value<String> status,
  Value<String?> imageUrl,
  Value<int> rowid,
});

final class $$RoomsTableReferences
    extends BaseReferences<_$AppDatabase, $RoomsTable, Room> {
  $$RoomsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BookingsTable, List<Booking>> _bookingsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.bookings,
          aliasName: $_aliasNameGenerator(
              db.rooms.roomNumber, db.bookings.roomNumber));

  $$BookingsTableProcessedTableManager get bookingsRefs {
    final manager = $$BookingsTableTableManager($_db, $_db.bookings)
        .filter((f) => f.roomNumber.roomNumber($_item.roomNumber));

    final cache = $_typedResult.readTableOrNull(_bookingsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$RoomsTableFilterComposer extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnFilters(column));

  Expression<bool> bookingsRefs(
      Expression<bool> Function($$BookingsTableFilterComposer f) f) {
    final $$BookingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.roomNumber,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.roomNumber,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableFilterComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RoomsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get type => $composableBuilder(
      column: $table.type, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get price => $composableBuilder(
      column: $table.price, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get imageUrl => $composableBuilder(
      column: $table.imageUrl, builder: (column) => ColumnOrderings(column));
}

class $$RoomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<double> get price =>
      $composableBuilder(column: $table.price, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  Expression<T> bookingsRefs<T extends Object>(
      Expression<T> Function($$BookingsTableAnnotationComposer a) f) {
    final $$BookingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.roomNumber,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.roomNumber,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableAnnotationComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$RoomsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $RoomsTable,
    Room,
    $$RoomsTableFilterComposer,
    $$RoomsTableOrderingComposer,
    $$RoomsTableAnnotationComposer,
    $$RoomsTableCreateCompanionBuilder,
    $$RoomsTableUpdateCompanionBuilder,
    (Room, $$RoomsTableReferences),
    Room,
    PrefetchHooks Function({bool bookingsRefs})> {
  $$RoomsTableTableManager(_$AppDatabase db, $RoomsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<String> roomNumber = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<double> price = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> imageUrl = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RoomsCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            roomNumber: roomNumber,
            type: type,
            price: price,
            status: status,
            imageUrl: imageUrl,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            required String roomNumber,
            required String type,
            required double price,
            required String status,
            Value<String?> imageUrl = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              RoomsCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            roomNumber: roomNumber,
            type: type,
            price: price,
            status: status,
            imageUrl: imageUrl,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$RoomsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({bookingsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (bookingsRefs) db.bookings],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookingsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable:
                            $$RoomsTableReferences._bookingsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$RoomsTableReferences(db, table, p0).bookingsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.roomNumber == item.roomNumber),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$RoomsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $RoomsTable,
    Room,
    $$RoomsTableFilterComposer,
    $$RoomsTableOrderingComposer,
    $$RoomsTableAnnotationComposer,
    $$RoomsTableCreateCompanionBuilder,
    $$RoomsTableUpdateCompanionBuilder,
    (Room, $$RoomsTableReferences),
    Room,
    PrefetchHooks Function({bool bookingsRefs})>;
typedef $$BookingsTableCreateCompanionBuilder = BookingsCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> serverBookingId,
  required String roomNumber,
  required String guestName,
  required String guestPhone,
  required String guestNationality,
  Value<String?> guestEmail,
  Value<String?> guestAddress,
  required String checkinDate,
  Value<String?> checkoutDate,
  required String status,
  Value<String?> notes,
  Value<int> calculatedNights,
});
typedef $$BookingsTableUpdateCompanionBuilder = BookingsCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> serverBookingId,
  Value<String> roomNumber,
  Value<String> guestName,
  Value<String> guestPhone,
  Value<String> guestNationality,
  Value<String?> guestEmail,
  Value<String?> guestAddress,
  Value<String> checkinDate,
  Value<String?> checkoutDate,
  Value<String> status,
  Value<String?> notes,
  Value<int> calculatedNights,
});

final class $$BookingsTableReferences
    extends BaseReferences<_$AppDatabase, $BookingsTable, Booking> {
  $$BookingsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RoomsTable _roomNumberTable(_$AppDatabase db) => db.rooms.createAlias(
      $_aliasNameGenerator(db.bookings.roomNumber, db.rooms.roomNumber));

  $$RoomsTableProcessedTableManager? get roomNumber {
    if ($_item.roomNumber == null) return null;
    final manager = $$RoomsTableTableManager($_db, $_db.rooms)
        .filter((f) => f.roomNumber($_item.roomNumber!));
    final item = $_typedResult.readTableOrNull(_roomNumberTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$BookingNotesTable, List<BookingNote>>
      _bookingNotesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.bookingNotes,
          aliasName:
              $_aliasNameGenerator(db.bookings.id, db.bookingNotes.bookingId));

  $$BookingNotesTableProcessedTableManager get bookingNotesRefs {
    final manager = $$BookingNotesTableTableManager($_db, $_db.bookingNotes)
        .filter((f) => f.bookingId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_bookingNotesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$PaymentsTable, List<Payment>> _paymentsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.payments,
          aliasName:
              $_aliasNameGenerator(db.bookings.id, db.payments.bookingLocalId));

  $$PaymentsTableProcessedTableManager get paymentsRefs {
    final manager = $$PaymentsTableTableManager($_db, $_db.payments)
        .filter((f) => f.bookingLocalId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_paymentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$BookingsTableFilterComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guestName => $composableBuilder(
      column: $table.guestName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guestPhone => $composableBuilder(
      column: $table.guestPhone, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guestNationality => $composableBuilder(
      column: $table.guestNationality,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guestEmail => $composableBuilder(
      column: $table.guestEmail, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get guestAddress => $composableBuilder(
      column: $table.guestAddress, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get checkinDate => $composableBuilder(
      column: $table.checkinDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get checkoutDate => $composableBuilder(
      column: $table.checkoutDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get calculatedNights => $composableBuilder(
      column: $table.calculatedNights,
      builder: (column) => ColumnFilters(column));

  $$RoomsTableFilterComposer get roomNumber {
    final $$RoomsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.roomNumber,
        referencedTable: $db.rooms,
        getReferencedColumn: (t) => t.roomNumber,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RoomsTableFilterComposer(
              $db: $db,
              $table: $db.rooms,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> bookingNotesRefs(
      Expression<bool> Function($$BookingNotesTableFilterComposer f) f) {
    final $$BookingNotesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookingNotes,
        getReferencedColumn: (t) => t.bookingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingNotesTableFilterComposer(
              $db: $db,
              $table: $db.bookingNotes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> paymentsRefs(
      Expression<bool> Function($$PaymentsTableFilterComposer f) f) {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.payments,
        getReferencedColumn: (t) => t.bookingLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PaymentsTableFilterComposer(
              $db: $db,
              $table: $db.payments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$BookingsTableOrderingComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guestName => $composableBuilder(
      column: $table.guestName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guestPhone => $composableBuilder(
      column: $table.guestPhone, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guestNationality => $composableBuilder(
      column: $table.guestNationality,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guestEmail => $composableBuilder(
      column: $table.guestEmail, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get guestAddress => $composableBuilder(
      column: $table.guestAddress,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get checkinDate => $composableBuilder(
      column: $table.checkinDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get checkoutDate => $composableBuilder(
      column: $table.checkoutDate,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get calculatedNights => $composableBuilder(
      column: $table.calculatedNights,
      builder: (column) => ColumnOrderings(column));

  $$RoomsTableOrderingComposer get roomNumber {
    final $$RoomsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.roomNumber,
        referencedTable: $db.rooms,
        getReferencedColumn: (t) => t.roomNumber,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RoomsTableOrderingComposer(
              $db: $db,
              $table: $db.rooms,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookingsTable> {
  $$BookingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId, builder: (column) => column);

  GeneratedColumn<String> get guestName =>
      $composableBuilder(column: $table.guestName, builder: (column) => column);

  GeneratedColumn<String> get guestPhone => $composableBuilder(
      column: $table.guestPhone, builder: (column) => column);

  GeneratedColumn<String> get guestNationality => $composableBuilder(
      column: $table.guestNationality, builder: (column) => column);

  GeneratedColumn<String> get guestEmail => $composableBuilder(
      column: $table.guestEmail, builder: (column) => column);

  GeneratedColumn<String> get guestAddress => $composableBuilder(
      column: $table.guestAddress, builder: (column) => column);

  GeneratedColumn<String> get checkinDate => $composableBuilder(
      column: $table.checkinDate, builder: (column) => column);

  GeneratedColumn<String> get checkoutDate => $composableBuilder(
      column: $table.checkoutDate, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get calculatedNights => $composableBuilder(
      column: $table.calculatedNights, builder: (column) => column);

  $$RoomsTableAnnotationComposer get roomNumber {
    final $$RoomsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.roomNumber,
        referencedTable: $db.rooms,
        getReferencedColumn: (t) => t.roomNumber,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$RoomsTableAnnotationComposer(
              $db: $db,
              $table: $db.rooms,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> bookingNotesRefs<T extends Object>(
      Expression<T> Function($$BookingNotesTableAnnotationComposer a) f) {
    final $$BookingNotesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.bookingNotes,
        getReferencedColumn: (t) => t.bookingId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingNotesTableAnnotationComposer(
              $db: $db,
              $table: $db.bookingNotes,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<T> paymentsRefs<T extends Object>(
      Expression<T> Function($$PaymentsTableAnnotationComposer a) f) {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.payments,
        getReferencedColumn: (t) => t.bookingLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PaymentsTableAnnotationComposer(
              $db: $db,
              $table: $db.payments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$BookingsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BookingsTable,
    Booking,
    $$BookingsTableFilterComposer,
    $$BookingsTableOrderingComposer,
    $$BookingsTableAnnotationComposer,
    $$BookingsTableCreateCompanionBuilder,
    $$BookingsTableUpdateCompanionBuilder,
    (Booking, $$BookingsTableReferences),
    Booking,
    PrefetchHooks Function(
        {bool roomNumber, bool bookingNotesRefs, bool paymentsRefs})> {
  $$BookingsTableTableManager(_$AppDatabase db, $BookingsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> serverBookingId = const Value.absent(),
            Value<String> roomNumber = const Value.absent(),
            Value<String> guestName = const Value.absent(),
            Value<String> guestPhone = const Value.absent(),
            Value<String> guestNationality = const Value.absent(),
            Value<String?> guestEmail = const Value.absent(),
            Value<String?> guestAddress = const Value.absent(),
            Value<String> checkinDate = const Value.absent(),
            Value<String?> checkoutDate = const Value.absent(),
            Value<String> status = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<int> calculatedNights = const Value.absent(),
          }) =>
              BookingsCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            serverBookingId: serverBookingId,
            roomNumber: roomNumber,
            guestName: guestName,
            guestPhone: guestPhone,
            guestNationality: guestNationality,
            guestEmail: guestEmail,
            guestAddress: guestAddress,
            checkinDate: checkinDate,
            checkoutDate: checkoutDate,
            status: status,
            notes: notes,
            calculatedNights: calculatedNights,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> serverBookingId = const Value.absent(),
            required String roomNumber,
            required String guestName,
            required String guestPhone,
            required String guestNationality,
            Value<String?> guestEmail = const Value.absent(),
            Value<String?> guestAddress = const Value.absent(),
            required String checkinDate,
            Value<String?> checkoutDate = const Value.absent(),
            required String status,
            Value<String?> notes = const Value.absent(),
            Value<int> calculatedNights = const Value.absent(),
          }) =>
              BookingsCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            serverBookingId: serverBookingId,
            roomNumber: roomNumber,
            guestName: guestName,
            guestPhone: guestPhone,
            guestNationality: guestNationality,
            guestEmail: guestEmail,
            guestAddress: guestAddress,
            checkinDate: checkinDate,
            checkoutDate: checkoutDate,
            status: status,
            notes: notes,
            calculatedNights: calculatedNights,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$BookingsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {roomNumber = false,
              bookingNotesRefs = false,
              paymentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (bookingNotesRefs) db.bookingNotes,
                if (paymentsRefs) db.payments
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (roomNumber) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.roomNumber,
                    referencedTable:
                        $$BookingsTableReferences._roomNumberTable(db),
                    referencedColumn: $$BookingsTableReferences
                        ._roomNumberTable(db)
                        .roomNumber,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (bookingNotesRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$BookingsTableReferences
                            ._bookingNotesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BookingsTableReferences(db, table, p0)
                                .bookingNotesRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.bookingId == item.id),
                        typedResults: items),
                  if (paymentsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable:
                            $$BookingsTableReferences._paymentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$BookingsTableReferences(db, table, p0)
                                .paymentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.bookingLocalId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$BookingsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BookingsTable,
    Booking,
    $$BookingsTableFilterComposer,
    $$BookingsTableOrderingComposer,
    $$BookingsTableAnnotationComposer,
    $$BookingsTableCreateCompanionBuilder,
    $$BookingsTableUpdateCompanionBuilder,
    (Booking, $$BookingsTableReferences),
    Booking,
    PrefetchHooks Function(
        {bool roomNumber, bool bookingNotesRefs, bool paymentsRefs})>;
typedef $$BookingNotesTableCreateCompanionBuilder = BookingNotesCompanion
    Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  required int bookingId,
  required String noteText,
  required String alertType,
  Value<String?> alertUntil,
  Value<int> isActive,
});
typedef $$BookingNotesTableUpdateCompanionBuilder = BookingNotesCompanion
    Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int> bookingId,
  Value<String> noteText,
  Value<String> alertType,
  Value<String?> alertUntil,
  Value<int> isActive,
});

final class $$BookingNotesTableReferences
    extends BaseReferences<_$AppDatabase, $BookingNotesTable, BookingNote> {
  $$BookingNotesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookingsTable _bookingIdTable(_$AppDatabase db) =>
      db.bookings.createAlias(
          $_aliasNameGenerator(db.bookingNotes.bookingId, db.bookings.id));

  $$BookingsTableProcessedTableManager? get bookingId {
    if ($_item.bookingId == null) return null;
    final manager = $$BookingsTableTableManager($_db, $_db.bookings)
        .filter((f) => f.id($_item.bookingId!));
    final item = $_typedResult.readTableOrNull(_bookingIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$BookingNotesTableFilterComposer
    extends Composer<_$AppDatabase, $BookingNotesTable> {
  $$BookingNotesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get noteText => $composableBuilder(
      column: $table.noteText, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alertType => $composableBuilder(
      column: $table.alertType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get alertUntil => $composableBuilder(
      column: $table.alertUntil, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnFilters(column));

  $$BookingsTableFilterComposer get bookingId {
    final $$BookingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableFilterComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookingNotesTableOrderingComposer
    extends Composer<_$AppDatabase, $BookingNotesTable> {
  $$BookingNotesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get noteText => $composableBuilder(
      column: $table.noteText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alertType => $composableBuilder(
      column: $table.alertType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get alertUntil => $composableBuilder(
      column: $table.alertUntil, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isActive => $composableBuilder(
      column: $table.isActive, builder: (column) => ColumnOrderings(column));

  $$BookingsTableOrderingComposer get bookingId {
    final $$BookingsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableOrderingComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookingNotesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BookingNotesTable> {
  $$BookingNotesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get noteText =>
      $composableBuilder(column: $table.noteText, builder: (column) => column);

  GeneratedColumn<String> get alertType =>
      $composableBuilder(column: $table.alertType, builder: (column) => column);

  GeneratedColumn<String> get alertUntil => $composableBuilder(
      column: $table.alertUntil, builder: (column) => column);

  GeneratedColumn<int> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$BookingsTableAnnotationComposer get bookingId {
    final $$BookingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableAnnotationComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$BookingNotesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BookingNotesTable,
    BookingNote,
    $$BookingNotesTableFilterComposer,
    $$BookingNotesTableOrderingComposer,
    $$BookingNotesTableAnnotationComposer,
    $$BookingNotesTableCreateCompanionBuilder,
    $$BookingNotesTableUpdateCompanionBuilder,
    (BookingNote, $$BookingNotesTableReferences),
    BookingNote,
    PrefetchHooks Function({bool bookingId})> {
  $$BookingNotesTableTableManager(_$AppDatabase db, $BookingNotesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookingNotesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookingNotesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookingNotesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int> bookingId = const Value.absent(),
            Value<String> noteText = const Value.absent(),
            Value<String> alertType = const Value.absent(),
            Value<String?> alertUntil = const Value.absent(),
            Value<int> isActive = const Value.absent(),
          }) =>
              BookingNotesCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            bookingId: bookingId,
            noteText: noteText,
            alertType: alertType,
            alertUntil: alertUntil,
            isActive: isActive,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            required int bookingId,
            required String noteText,
            required String alertType,
            Value<String?> alertUntil = const Value.absent(),
            Value<int> isActive = const Value.absent(),
          }) =>
              BookingNotesCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            bookingId: bookingId,
            noteText: noteText,
            alertType: alertType,
            alertUntil: alertUntil,
            isActive: isActive,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$BookingNotesTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({bookingId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookingId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookingId,
                    referencedTable:
                        $$BookingNotesTableReferences._bookingIdTable(db),
                    referencedColumn:
                        $$BookingNotesTableReferences._bookingIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$BookingNotesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BookingNotesTable,
    BookingNote,
    $$BookingNotesTableFilterComposer,
    $$BookingNotesTableOrderingComposer,
    $$BookingNotesTableAnnotationComposer,
    $$BookingNotesTableCreateCompanionBuilder,
    $$BookingNotesTableUpdateCompanionBuilder,
    (BookingNote, $$BookingNotesTableReferences),
    BookingNote,
    PrefetchHooks Function({bool bookingId})>;
typedef $$EmployeesTableCreateCompanionBuilder = EmployeesCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  required String name,
  required double basicSalary,
  required String status,
});
typedef $$EmployeesTableUpdateCompanionBuilder = EmployeesCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<String> name,
  Value<double> basicSalary,
  Value<String> status,
});

class $$EmployeesTableFilterComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get basicSalary => $composableBuilder(
      column: $table.basicSalary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnFilters(column));
}

class $$EmployeesTableOrderingComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get basicSalary => $composableBuilder(
      column: $table.basicSalary, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get status => $composableBuilder(
      column: $table.status, builder: (column) => ColumnOrderings(column));
}

class $$EmployeesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EmployeesTable> {
  $$EmployeesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<double> get basicSalary => $composableBuilder(
      column: $table.basicSalary, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$EmployeesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $EmployeesTable,
    Employee,
    $$EmployeesTableFilterComposer,
    $$EmployeesTableOrderingComposer,
    $$EmployeesTableAnnotationComposer,
    $$EmployeesTableCreateCompanionBuilder,
    $$EmployeesTableUpdateCompanionBuilder,
    (Employee, BaseReferences<_$AppDatabase, $EmployeesTable, Employee>),
    Employee,
    PrefetchHooks Function()> {
  $$EmployeesTableTableManager(_$AppDatabase db, $EmployeesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EmployeesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EmployeesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EmployeesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<double> basicSalary = const Value.absent(),
            Value<String> status = const Value.absent(),
          }) =>
              EmployeesCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            name: name,
            basicSalary: basicSalary,
            status: status,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            required String name,
            required double basicSalary,
            required String status,
          }) =>
              EmployeesCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            name: name,
            basicSalary: basicSalary,
            status: status,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$EmployeesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $EmployeesTable,
    Employee,
    $$EmployeesTableFilterComposer,
    $$EmployeesTableOrderingComposer,
    $$EmployeesTableAnnotationComposer,
    $$EmployeesTableCreateCompanionBuilder,
    $$EmployeesTableUpdateCompanionBuilder,
    (Employee, BaseReferences<_$AppDatabase, $EmployeesTable, Employee>),
    Employee,
    PrefetchHooks Function()>;
typedef $$ExpensesTableCreateCompanionBuilder = ExpensesCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  required String expenseType,
  Value<int?> relatedId,
  required String description,
  required double amount,
  required String date,
  Value<int?> cashTransactionId,
});
typedef $$ExpensesTableUpdateCompanionBuilder = ExpensesCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<String> expenseType,
  Value<int?> relatedId,
  Value<String> description,
  Value<double> amount,
  Value<String> date,
  Value<int?> cashTransactionId,
});

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expenseType => $composableBuilder(
      column: $table.expenseType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get relatedId => $composableBuilder(
      column: $table.relatedId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cashTransactionId => $composableBuilder(
      column: $table.cashTransactionId,
      builder: (column) => ColumnFilters(column));
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expenseType => $composableBuilder(
      column: $table.expenseType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get relatedId => $composableBuilder(
      column: $table.relatedId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get date => $composableBuilder(
      column: $table.date, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cashTransactionId => $composableBuilder(
      column: $table.cashTransactionId,
      builder: (column) => ColumnOrderings(column));
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expenseType => $composableBuilder(
      column: $table.expenseType, builder: (column) => column);

  GeneratedColumn<int> get relatedId =>
      $composableBuilder(column: $table.relatedId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<int> get cashTransactionId => $composableBuilder(
      column: $table.cashTransactionId, builder: (column) => column);
}

class $$ExpensesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()> {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<String> expenseType = const Value.absent(),
            Value<int?> relatedId = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> date = const Value.absent(),
            Value<int?> cashTransactionId = const Value.absent(),
          }) =>
              ExpensesCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            expenseType: expenseType,
            relatedId: relatedId,
            description: description,
            amount: amount,
            date: date,
            cashTransactionId: cashTransactionId,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            required String expenseType,
            Value<int?> relatedId = const Value.absent(),
            required String description,
            required double amount,
            required String date,
            Value<int?> cashTransactionId = const Value.absent(),
          }) =>
              ExpensesCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            expenseType: expenseType,
            relatedId: relatedId,
            description: description,
            amount: amount,
            date: date,
            cashTransactionId: cashTransactionId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ExpensesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ExpensesTable,
    Expense,
    $$ExpensesTableFilterComposer,
    $$ExpensesTableOrderingComposer,
    $$ExpensesTableAnnotationComposer,
    $$ExpensesTableCreateCompanionBuilder,
    $$ExpensesTableUpdateCompanionBuilder,
    (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
    Expense,
    PrefetchHooks Function()>;
typedef $$CashTransactionsTableCreateCompanionBuilder
    = CashTransactionsCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> registerId,
  required String transactionType,
  required double amount,
  Value<String?> referenceType,
  Value<int?> referenceId,
  Value<String?> description,
  required String transactionTime,
  Value<int?> createdBy,
});
typedef $$CashTransactionsTableUpdateCompanionBuilder
    = CashTransactionsCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> registerId,
  Value<String> transactionType,
  Value<double> amount,
  Value<String?> referenceType,
  Value<int?> referenceId,
  Value<String?> description,
  Value<String> transactionTime,
  Value<int?> createdBy,
});

final class $$CashTransactionsTableReferences extends BaseReferences<
    _$AppDatabase, $CashTransactionsTable, CashTransaction> {
  $$CashTransactionsTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PaymentsTable, List<Payment>> _paymentsRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.payments,
          aliasName: $_aliasNameGenerator(
              db.cashTransactions.id, db.payments.cashTransactionLocalId));

  $$PaymentsTableProcessedTableManager get paymentsRefs {
    final manager = $$PaymentsTableTableManager($_db, $_db.payments)
        .filter((f) => f.cashTransactionLocalId.id($_item.id));

    final cache = $_typedResult.readTableOrNull(_paymentsRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$CashTransactionsTableFilterComposer
    extends Composer<_$AppDatabase, $CashTransactionsTable> {
  $$CashTransactionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get registerId => $composableBuilder(
      column: $table.registerId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transactionType => $composableBuilder(
      column: $table.transactionType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get referenceType => $composableBuilder(
      column: $table.referenceType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get transactionTime => $composableBuilder(
      column: $table.transactionTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdBy => $composableBuilder(
      column: $table.createdBy, builder: (column) => ColumnFilters(column));

  Expression<bool> paymentsRefs(
      Expression<bool> Function($$PaymentsTableFilterComposer f) f) {
    final $$PaymentsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.payments,
        getReferencedColumn: (t) => t.cashTransactionLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PaymentsTableFilterComposer(
              $db: $db,
              $table: $db.payments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CashTransactionsTableOrderingComposer
    extends Composer<_$AppDatabase, $CashTransactionsTable> {
  $$CashTransactionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get registerId => $composableBuilder(
      column: $table.registerId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transactionType => $composableBuilder(
      column: $table.transactionType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get referenceType => $composableBuilder(
      column: $table.referenceType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get transactionTime => $composableBuilder(
      column: $table.transactionTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdBy => $composableBuilder(
      column: $table.createdBy, builder: (column) => ColumnOrderings(column));
}

class $$CashTransactionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CashTransactionsTable> {
  $$CashTransactionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get registerId => $composableBuilder(
      column: $table.registerId, builder: (column) => column);

  GeneratedColumn<String> get transactionType => $composableBuilder(
      column: $table.transactionType, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get referenceType => $composableBuilder(
      column: $table.referenceType, builder: (column) => column);

  GeneratedColumn<int> get referenceId => $composableBuilder(
      column: $table.referenceId, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
      column: $table.description, builder: (column) => column);

  GeneratedColumn<String> get transactionTime => $composableBuilder(
      column: $table.transactionTime, builder: (column) => column);

  GeneratedColumn<int> get createdBy =>
      $composableBuilder(column: $table.createdBy, builder: (column) => column);

  Expression<T> paymentsRefs<T extends Object>(
      Expression<T> Function($$PaymentsTableAnnotationComposer a) f) {
    final $$PaymentsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.payments,
        getReferencedColumn: (t) => t.cashTransactionLocalId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$PaymentsTableAnnotationComposer(
              $db: $db,
              $table: $db.payments,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$CashTransactionsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CashTransactionsTable,
    CashTransaction,
    $$CashTransactionsTableFilterComposer,
    $$CashTransactionsTableOrderingComposer,
    $$CashTransactionsTableAnnotationComposer,
    $$CashTransactionsTableCreateCompanionBuilder,
    $$CashTransactionsTableUpdateCompanionBuilder,
    (CashTransaction, $$CashTransactionsTableReferences),
    CashTransaction,
    PrefetchHooks Function({bool paymentsRefs})> {
  $$CashTransactionsTableTableManager(
      _$AppDatabase db, $CashTransactionsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CashTransactionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CashTransactionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CashTransactionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> registerId = const Value.absent(),
            Value<String> transactionType = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String?> referenceType = const Value.absent(),
            Value<int?> referenceId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            Value<String> transactionTime = const Value.absent(),
            Value<int?> createdBy = const Value.absent(),
          }) =>
              CashTransactionsCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            registerId: registerId,
            transactionType: transactionType,
            amount: amount,
            referenceType: referenceType,
            referenceId: referenceId,
            description: description,
            transactionTime: transactionTime,
            createdBy: createdBy,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> registerId = const Value.absent(),
            required String transactionType,
            required double amount,
            Value<String?> referenceType = const Value.absent(),
            Value<int?> referenceId = const Value.absent(),
            Value<String?> description = const Value.absent(),
            required String transactionTime,
            Value<int?> createdBy = const Value.absent(),
          }) =>
              CashTransactionsCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            registerId: registerId,
            transactionType: transactionType,
            amount: amount,
            referenceType: referenceType,
            referenceId: referenceId,
            description: description,
            transactionTime: transactionTime,
            createdBy: createdBy,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$CashTransactionsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({paymentsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (paymentsRefs) db.payments],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (paymentsRefs)
                    await $_getPrefetchedData(
                        currentTable: table,
                        referencedTable: $$CashTransactionsTableReferences
                            ._paymentsRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$CashTransactionsTableReferences(db, table, p0)
                                .paymentsRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems.where(
                                (e) => e.cashTransactionLocalId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$CashTransactionsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CashTransactionsTable,
    CashTransaction,
    $$CashTransactionsTableFilterComposer,
    $$CashTransactionsTableOrderingComposer,
    $$CashTransactionsTableAnnotationComposer,
    $$CashTransactionsTableCreateCompanionBuilder,
    $$CashTransactionsTableUpdateCompanionBuilder,
    (CashTransaction, $$CashTransactionsTableReferences),
    CashTransaction,
    PrefetchHooks Function({bool paymentsRefs})>;
typedef $$PaymentsTableCreateCompanionBuilder = PaymentsCompanion Function({
  required String localUuid,
  Value<int?> serverId,
  required int createdAt,
  required int updatedAt,
  Value<int?> deletedAt,
  required int lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> serverPaymentId,
  Value<int?> bookingLocalId,
  Value<int?> serverBookingId,
  Value<String?> roomNumber,
  required double amount,
  required String paymentDate,
  Value<String?> notes,
  required String paymentMethod,
  required String revenueType,
  Value<int?> cashTransactionLocalId,
  Value<int?> cashTransactionServerId,
});
typedef $$PaymentsTableUpdateCompanionBuilder = PaymentsCompanion Function({
  Value<String> localUuid,
  Value<int?> serverId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int?> deletedAt,
  Value<int> lastModified,
  Value<int> version,
  Value<String> origin,
  Value<int> id,
  Value<int?> serverPaymentId,
  Value<int?> bookingLocalId,
  Value<int?> serverBookingId,
  Value<String?> roomNumber,
  Value<double> amount,
  Value<String> paymentDate,
  Value<String?> notes,
  Value<String> paymentMethod,
  Value<String> revenueType,
  Value<int?> cashTransactionLocalId,
  Value<int?> cashTransactionServerId,
});

final class $$PaymentsTableReferences
    extends BaseReferences<_$AppDatabase, $PaymentsTable, Payment> {
  $$PaymentsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $BookingsTable _bookingLocalIdTable(_$AppDatabase db) =>
      db.bookings.createAlias(
          $_aliasNameGenerator(db.payments.bookingLocalId, db.bookings.id));

  $$BookingsTableProcessedTableManager? get bookingLocalId {
    if ($_item.bookingLocalId == null) return null;
    final manager = $$BookingsTableTableManager($_db, $_db.bookings)
        .filter((f) => f.id($_item.bookingLocalId!));
    final item = $_typedResult.readTableOrNull(_bookingLocalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $CashTransactionsTable _cashTransactionLocalIdTable(
          _$AppDatabase db) =>
      db.cashTransactions.createAlias($_aliasNameGenerator(
          db.payments.cashTransactionLocalId, db.cashTransactions.id));

  $$CashTransactionsTableProcessedTableManager? get cashTransactionLocalId {
    if ($_item.cashTransactionLocalId == null) return null;
    final manager =
        $$CashTransactionsTableTableManager($_db, $_db.cashTransactions)
            .filter((f) => f.id($_item.cashTransactionLocalId!));
    final item =
        $_typedResult.readTableOrNull(_cashTransactionLocalIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$PaymentsTableFilterComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverPaymentId => $composableBuilder(
      column: $table.serverPaymentId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentDate => $composableBuilder(
      column: $table.paymentDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get revenueType => $composableBuilder(
      column: $table.revenueType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get cashTransactionServerId => $composableBuilder(
      column: $table.cashTransactionServerId,
      builder: (column) => ColumnFilters(column));

  $$BookingsTableFilterComposer get bookingLocalId {
    final $$BookingsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingLocalId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableFilterComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CashTransactionsTableFilterComposer get cashTransactionLocalId {
    final $$CashTransactionsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.cashTransactionLocalId,
        referencedTable: $db.cashTransactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CashTransactionsTableFilterComposer(
              $db: $db,
              $table: $db.cashTransactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PaymentsTableOrderingComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastModified => $composableBuilder(
      column: $table.lastModified,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get origin => $composableBuilder(
      column: $table.origin, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverPaymentId => $composableBuilder(
      column: $table.serverPaymentId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get amount => $composableBuilder(
      column: $table.amount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentDate => $composableBuilder(
      column: $table.paymentDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get revenueType => $composableBuilder(
      column: $table.revenueType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get cashTransactionServerId => $composableBuilder(
      column: $table.cashTransactionServerId,
      builder: (column) => ColumnOrderings(column));

  $$BookingsTableOrderingComposer get bookingLocalId {
    final $$BookingsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingLocalId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableOrderingComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CashTransactionsTableOrderingComposer get cashTransactionLocalId {
    final $$CashTransactionsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.cashTransactionLocalId,
        referencedTable: $db.cashTransactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CashTransactionsTableOrderingComposer(
              $db: $db,
              $table: $db.cashTransactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PaymentsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PaymentsTable> {
  $$PaymentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<int> get lastModified => $composableBuilder(
      column: $table.lastModified, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get serverPaymentId => $composableBuilder(
      column: $table.serverPaymentId, builder: (column) => column);

  GeneratedColumn<int> get serverBookingId => $composableBuilder(
      column: $table.serverBookingId, builder: (column) => column);

  GeneratedColumn<String> get roomNumber => $composableBuilder(
      column: $table.roomNumber, builder: (column) => column);

  GeneratedColumn<double> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<String> get paymentDate => $composableBuilder(
      column: $table.paymentDate, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<String> get paymentMethod => $composableBuilder(
      column: $table.paymentMethod, builder: (column) => column);

  GeneratedColumn<String> get revenueType => $composableBuilder(
      column: $table.revenueType, builder: (column) => column);

  GeneratedColumn<int> get cashTransactionServerId => $composableBuilder(
      column: $table.cashTransactionServerId, builder: (column) => column);

  $$BookingsTableAnnotationComposer get bookingLocalId {
    final $$BookingsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.bookingLocalId,
        referencedTable: $db.bookings,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$BookingsTableAnnotationComposer(
              $db: $db,
              $table: $db.bookings,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$CashTransactionsTableAnnotationComposer get cashTransactionLocalId {
    final $$CashTransactionsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.cashTransactionLocalId,
        referencedTable: $db.cashTransactions,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$CashTransactionsTableAnnotationComposer(
              $db: $db,
              $table: $db.cashTransactions,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$PaymentsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PaymentsTable,
    Payment,
    $$PaymentsTableFilterComposer,
    $$PaymentsTableOrderingComposer,
    $$PaymentsTableAnnotationComposer,
    $$PaymentsTableCreateCompanionBuilder,
    $$PaymentsTableUpdateCompanionBuilder,
    (Payment, $$PaymentsTableReferences),
    Payment,
    PrefetchHooks Function(
        {bool bookingLocalId, bool cashTransactionLocalId})> {
  $$PaymentsTableTableManager(_$AppDatabase db, $PaymentsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PaymentsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PaymentsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PaymentsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int?> deletedAt = const Value.absent(),
            Value<int> lastModified = const Value.absent(),
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> serverPaymentId = const Value.absent(),
            Value<int?> bookingLocalId = const Value.absent(),
            Value<int?> serverBookingId = const Value.absent(),
            Value<String?> roomNumber = const Value.absent(),
            Value<double> amount = const Value.absent(),
            Value<String> paymentDate = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<String> paymentMethod = const Value.absent(),
            Value<String> revenueType = const Value.absent(),
            Value<int?> cashTransactionLocalId = const Value.absent(),
            Value<int?> cashTransactionServerId = const Value.absent(),
          }) =>
              PaymentsCompanion(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            serverPaymentId: serverPaymentId,
            bookingLocalId: bookingLocalId,
            serverBookingId: serverBookingId,
            roomNumber: roomNumber,
            amount: amount,
            paymentDate: paymentDate,
            notes: notes,
            paymentMethod: paymentMethod,
            revenueType: revenueType,
            cashTransactionLocalId: cashTransactionLocalId,
            cashTransactionServerId: cashTransactionServerId,
          ),
          createCompanionCallback: ({
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int?> deletedAt = const Value.absent(),
            required int lastModified,
            Value<int> version = const Value.absent(),
            Value<String> origin = const Value.absent(),
            Value<int> id = const Value.absent(),
            Value<int?> serverPaymentId = const Value.absent(),
            Value<int?> bookingLocalId = const Value.absent(),
            Value<int?> serverBookingId = const Value.absent(),
            Value<String?> roomNumber = const Value.absent(),
            required double amount,
            required String paymentDate,
            Value<String?> notes = const Value.absent(),
            required String paymentMethod,
            required String revenueType,
            Value<int?> cashTransactionLocalId = const Value.absent(),
            Value<int?> cashTransactionServerId = const Value.absent(),
          }) =>
              PaymentsCompanion.insert(
            localUuid: localUuid,
            serverId: serverId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            lastModified: lastModified,
            version: version,
            origin: origin,
            id: id,
            serverPaymentId: serverPaymentId,
            bookingLocalId: bookingLocalId,
            serverBookingId: serverBookingId,
            roomNumber: roomNumber,
            amount: amount,
            paymentDate: paymentDate,
            notes: notes,
            paymentMethod: paymentMethod,
            revenueType: revenueType,
            cashTransactionLocalId: cashTransactionLocalId,
            cashTransactionServerId: cashTransactionServerId,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$PaymentsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: (
              {bookingLocalId = false, cashTransactionLocalId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (bookingLocalId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.bookingLocalId,
                    referencedTable:
                        $$PaymentsTableReferences._bookingLocalIdTable(db),
                    referencedColumn:
                        $$PaymentsTableReferences._bookingLocalIdTable(db).id,
                  ) as T;
                }
                if (cashTransactionLocalId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.cashTransactionLocalId,
                    referencedTable: $$PaymentsTableReferences
                        ._cashTransactionLocalIdTable(db),
                    referencedColumn: $$PaymentsTableReferences
                        ._cashTransactionLocalIdTable(db)
                        .id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$PaymentsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $PaymentsTable,
    Payment,
    $$PaymentsTableFilterComposer,
    $$PaymentsTableOrderingComposer,
    $$PaymentsTableAnnotationComposer,
    $$PaymentsTableCreateCompanionBuilder,
    $$PaymentsTableUpdateCompanionBuilder,
    (Payment, $$PaymentsTableReferences),
    Payment,
    PrefetchHooks Function({bool bookingLocalId, bool cashTransactionLocalId})>;
typedef $$OutboxTableCreateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  required String entity,
  required String op,
  required String localUuid,
  Value<int?> serverId,
  required String payload,
  required int clientTs,
  Value<int> attempts,
  Value<String?> lastError,
});
typedef $$OutboxTableUpdateCompanionBuilder = OutboxCompanion Function({
  Value<int> id,
  Value<String> entity,
  Value<String> op,
  Value<String> localUuid,
  Value<int?> serverId,
  Value<String> payload,
  Value<int> clientTs,
  Value<int> attempts,
  Value<String?> lastError,
});

class $$OutboxTableFilterComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get op => $composableBuilder(
      column: $table.op, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get clientTs => $composableBuilder(
      column: $table.clientTs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));
}

class $$OutboxTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entity => $composableBuilder(
      column: $table.entity, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get op => $composableBuilder(
      column: $table.op, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get localUuid => $composableBuilder(
      column: $table.localUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get payload => $composableBuilder(
      column: $table.payload, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get clientTs => $composableBuilder(
      column: $table.clientTs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));
}

class $$OutboxTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboxTable> {
  $$OutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get localUuid =>
      $composableBuilder(column: $table.localUuid, builder: (column) => column);

  GeneratedColumn<int> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get clientTs =>
      $composableBuilder(column: $table.clientTs, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$OutboxTableTableManager extends RootTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxData,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
    OutboxData,
    PrefetchHooks Function()> {
  $$OutboxTableTableManager(_$AppDatabase db, $OutboxTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> entity = const Value.absent(),
            Value<String> op = const Value.absent(),
            Value<String> localUuid = const Value.absent(),
            Value<int?> serverId = const Value.absent(),
            Value<String> payload = const Value.absent(),
            Value<int> clientTs = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxCompanion(
            id: id,
            entity: entity,
            op: op,
            localUuid: localUuid,
            serverId: serverId,
            payload: payload,
            clientTs: clientTs,
            attempts: attempts,
            lastError: lastError,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String entity,
            required String op,
            required String localUuid,
            Value<int?> serverId = const Value.absent(),
            required String payload,
            required int clientTs,
            Value<int> attempts = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
          }) =>
              OutboxCompanion.insert(
            id: id,
            entity: entity,
            op: op,
            localUuid: localUuid,
            serverId: serverId,
            payload: payload,
            clientTs: clientTs,
            attempts: attempts,
            lastError: lastError,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$OutboxTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $OutboxTable,
    OutboxData,
    $$OutboxTableFilterComposer,
    $$OutboxTableOrderingComposer,
    $$OutboxTableAnnotationComposer,
    $$OutboxTableCreateCompanionBuilder,
    $$OutboxTableUpdateCompanionBuilder,
    (OutboxData, BaseReferences<_$AppDatabase, $OutboxTable, OutboxData>),
    OutboxData,
    PrefetchHooks Function()>;
typedef $$SyncStateTableCreateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> lastServerTs,
  Value<int> lastPullTs,
  Value<int> lastPushTs,
  Value<int> isSyncing,
  Value<int> version,
});
typedef $$SyncStateTableUpdateCompanionBuilder = SyncStateCompanion Function({
  Value<int> id,
  Value<int> lastServerTs,
  Value<int> lastPullTs,
  Value<int> lastPushTs,
  Value<int> isSyncing,
  Value<int> version,
});

class $$SyncStateTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastServerTs => $composableBuilder(
      column: $table.lastServerTs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPullTs => $composableBuilder(
      column: $table.lastPullTs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastPushTs => $composableBuilder(
      column: $table.lastPushTs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnFilters(column));
}

class $$SyncStateTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastServerTs => $composableBuilder(
      column: $table.lastServerTs,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPullTs => $composableBuilder(
      column: $table.lastPullTs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastPushTs => $composableBuilder(
      column: $table.lastPushTs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get isSyncing => $composableBuilder(
      column: $table.isSyncing, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get version => $composableBuilder(
      column: $table.version, builder: (column) => ColumnOrderings(column));
}

class $$SyncStateTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStateTable> {
  $$SyncStateTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get lastServerTs => $composableBuilder(
      column: $table.lastServerTs, builder: (column) => column);

  GeneratedColumn<int> get lastPullTs => $composableBuilder(
      column: $table.lastPullTs, builder: (column) => column);

  GeneratedColumn<int> get lastPushTs => $composableBuilder(
      column: $table.lastPushTs, builder: (column) => column);

  GeneratedColumn<int> get isSyncing =>
      $composableBuilder(column: $table.isSyncing, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$SyncStateTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()> {
  $$SyncStateTableTableManager(_$AppDatabase db, $SyncStateTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStateTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStateTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStateTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> lastServerTs = const Value.absent(),
            Value<int> lastPullTs = const Value.absent(),
            Value<int> lastPushTs = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<int> version = const Value.absent(),
          }) =>
              SyncStateCompanion(
            id: id,
            lastServerTs: lastServerTs,
            lastPullTs: lastPullTs,
            lastPushTs: lastPushTs,
            isSyncing: isSyncing,
            version: version,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<int> lastServerTs = const Value.absent(),
            Value<int> lastPullTs = const Value.absent(),
            Value<int> lastPushTs = const Value.absent(),
            Value<int> isSyncing = const Value.absent(),
            Value<int> version = const Value.absent(),
          }) =>
              SyncStateCompanion.insert(
            id: id,
            lastServerTs: lastServerTs,
            lastPullTs: lastPullTs,
            lastPushTs: lastPushTs,
            isSyncing: isSyncing,
            version: version,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncStateTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncStateTable,
    SyncStateData,
    $$SyncStateTableFilterComposer,
    $$SyncStateTableOrderingComposer,
    $$SyncStateTableAnnotationComposer,
    $$SyncStateTableCreateCompanionBuilder,
    $$SyncStateTableUpdateCompanionBuilder,
    (
      SyncStateData,
      BaseReferences<_$AppDatabase, $SyncStateTable, SyncStateData>
    ),
    SyncStateData,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db, _db.rooms);
  $$BookingsTableTableManager get bookings =>
      $$BookingsTableTableManager(_db, _db.bookings);
  $$BookingNotesTableTableManager get bookingNotes =>
      $$BookingNotesTableTableManager(_db, _db.bookingNotes);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db, _db.employees);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$CashTransactionsTableTableManager get cashTransactions =>
      $$CashTransactionsTableTableManager(_db, _db.cashTransactions);
  $$PaymentsTableTableManager get payments =>
      $$PaymentsTableTableManager(_db, _db.payments);
  $$OutboxTableTableManager get outbox =>
      $$OutboxTableTableManager(_db, _db.outbox);
  $$SyncStateTableTableManager get syncState =>
      $$SyncStateTableTableManager(_db, _db.syncState);
}
