// نماذج البيانات لـ Appwrite

/// نموذج الجهاز المسجل
class AppwriteDevice {
  AppwriteDevice({      required this.id,
      required this.deviceName,
      required this.deviceModel,
      required this.osVersion,
      required this.lastSeen,
      required this.status,
      required this.createdAt,
      required this.updatedAt,
      required this.version,
      this.lastActive,
      this.origin,
      this.localUuid,
  });

  factory AppwriteDevice.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value, {DateTime? fallback}) {
      if (value == null) {
        return fallback ?? DateTime.now();
      }
      if (value is int) {
        return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true).toLocal();
      }
      if (value is double) {
        return DateTime.fromMillisecondsSinceEpoch((value * 1000).round(), isUtc: true).toLocal();
      }
      if (value is String && value.isNotEmpty) {
        final parsed = DateTime.tryParse(value);
        if (parsed != null) {
          return parsed.toLocal();
        }
      }
      return fallback ?? DateTime.now();
    }

    return AppwriteDevice(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      deviceName: (json['deviceName'] as String?) ?? '',
      deviceModel: (json['deviceModel'] as String?) ?? '',
      osVersion: (json['osVersion'] as String?) ?? '',
      lastSeen: parseDate(json['lastSeen'], fallback: DateTime.now()),
      lastActive: json.containsKey('lastActive') ? parseDate(json['lastActive']) : null,
      status: (json['status'] as String?) ?? 'active',
      createdAt: parseDate(json['createdAt'], fallback: DateTime.now()),
      updatedAt: parseDate(json['updatedAt'], fallback: DateTime.now()),
      version: (json['version'] is num)
          ? (json['version'] as num).toInt()
          : int.tryParse('${json['version'] ?? 1}') ?? 1,
      origin: json['origin']?.toString(),
      localUuid: json['localUuid']?.toString(),
    );
  }
  final String id;
  final String deviceName;
  final String deviceModel;
  final String osVersion;
  final DateTime lastSeen;
  final DateTime? lastActive;
  final String status; // 'active', 'inactive', 'suspended'
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final String? origin;
  final String? localUuid;

  Map<String, dynamic> toJson() {
    int toEpoch(DateTime value) => value.toUtc().millisecondsSinceEpoch ~/ 1000;

    return {
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'osVersion': osVersion,
      'lastSeen': lastSeen.toIso8601String(),
      if (lastActive != null) 'lastActive': toEpoch(lastActive!),
      'status': status,
      'createdAt': toEpoch(createdAt),
      'updatedAt': toEpoch(updatedAt),
      'version': version,
      if (origin != null) 'origin': origin,
      if (localUuid != null) 'localUuid': localUuid,
    };
  }
}

/// نموذج سجل المزامنة
class AppwriteSyncLog {
  AppwriteSyncLog({      required this.id,
      required this.deviceId,
      required this.syncType,
      required this.startTime,
      required this.status,
      this.endTime,
      this.recordsPushed = 0,
      this.recordsPulled = 0,
      this.conflicts = 0,
      this.errorMessage,
      this.details,
  });

  factory AppwriteSyncLog.fromJson(Map<String, dynamic> json) {
    return AppwriteSyncLog(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      deviceId: (json['deviceId'] as String?) ?? '',
      syncType: (json['syncType'] as String?) ?? 'full',
      startTime: DateTime.parse((json['startTime'] as String?) ?? DateTime.now().toIso8601String()),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime'] as String) : null,
      status: (json['status'] as String?) ?? 'in_progress',
      recordsPushed: (json['recordsPushed'] as num?)?.toInt() ?? 0,
      recordsPulled: (json['recordsPulled'] as num?)?.toInt() ?? 0,
      conflicts: (json['conflicts'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
      details: json['details'] as Map<String, dynamic>?,
    );
  }
  final String id;
  final String deviceId;
  final String syncType; // 'push', 'pull', 'full'
  final DateTime startTime;
  final DateTime? endTime;
  final String status; // 'in_progress', 'completed', 'failed', 'partial'
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final Map<String, dynamic>? details;

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'syncType': syncType,
      'startTime': startTime.toIso8601String(),
      if (endTime != null) 'endTime': endTime!.toIso8601String(),
      'status': status,
      'recordsPushed': recordsPushed,
      'recordsPulled': recordsPulled,
      'conflicts': conflicts,
      if (errorMessage != null) 'errorMessage': errorMessage,
      if (details != null) 'details': details,
    };
  }

  Duration? get duration => endTime?.difference(startTime);
}

/// نموذج الغرفة (مبسط)
class AppwriteRoom {
  AppwriteRoom({
    required this.id,
    required this.roomNumber,
    required this.type,
    required this.status,
    required this.price,
    required this.floor,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteRoom.fromJson(Map<String, dynamic> json) {
    return AppwriteRoom(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      roomNumber: (json['roomNumber'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      price: ((json['price'] as num?) ?? 0).toDouble(),
      floor: (json['floor'] as num?)?.toInt() ?? 0,
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String roomNumber;
  final String type;
  final String status;
  final double price;
  final int floor;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'roomNumber': roomNumber,
      'type': type,
      'status': status,
      'price': price,
      'floor': floor,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج الحجز (مبسط)
class AppwriteBooking {
  AppwriteBooking({
    required this.id,
    required this.roomId,
    required this.guestName,
    required this.guestPhone,
    required this.checkIn,
    required this.checkOut,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteBooking.fromJson(Map<String, dynamic> json) {
    return AppwriteBooking(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      roomId: (json['roomId'] as String?) ?? '',
      guestName: (json['guestName'] as String?) ?? '',
      guestPhone: (json['guestPhone'] as String?) ?? '',
      checkIn: DateTime.parse((json['checkIn'] as String?) ?? DateTime.now().toIso8601String()),
      checkOut: DateTime.parse((json['checkOut'] as String?) ?? DateTime.now().toIso8601String()),
      status: (json['status'] as String?) ?? '',
      totalAmount: ((json['totalAmount'] as num?) ?? 0).toDouble(),
      paidAmount: ((json['paidAmount'] as num?) ?? 0).toDouble(),
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String roomId;
  final String guestName;
  final String guestPhone;
  final DateTime checkIn;
  final DateTime checkOut;
  final String status;
  final double totalAmount;
  final double paidAmount;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'roomId': roomId,
      'guestName': guestName,
      'guestPhone': guestPhone,
      'checkIn': checkIn.toIso8601String(),
      'checkOut': checkOut.toIso8601String(),
      'status': status,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج الدفع (مبسط)
class AppwritePayment {
  AppwritePayment({
    required this.id,
    required this.bookingId,
    required this.amount,
    required this.paymentMethod,
    required this.paymentDate,
    this.notes,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwritePayment.fromJson(Map<String, dynamic> json) {
    return AppwritePayment(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      bookingId: (json['bookingId'] as String?) ?? '',
      amount: ((json['amount'] as num?) ?? 0).toDouble(),
      paymentMethod: (json['paymentMethod'] as String?) ?? '',
      paymentDate: DateTime.parse((json['paymentDate'] as String?) ?? DateTime.now().toIso8601String()),
      notes: json['notes'] as String?,
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String bookingId;
  final double amount;
  final String paymentMethod;
  final DateTime paymentDate;
  final String? notes;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'paymentDate': paymentDate.toIso8601String(),
      if (notes != null) 'notes': notes,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج المصروف (مبسط)
class AppwriteExpense {
  AppwriteExpense({
    required this.id,
    required this.category,
    required this.amount,
    required this.description,
    required this.expenseDate,
    this.employeeId,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteExpense.fromJson(Map<String, dynamic> json) {
    return AppwriteExpense(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      category: (json['category'] as String?) ?? '',
      amount: ((json['amount'] as num?) ?? 0).toDouble(),
      description: (json['description'] as String?) ?? '',
      expenseDate: DateTime.parse((json['expenseDate'] as String?) ?? DateTime.now().toIso8601String()),
      employeeId: json['employeeId'] as String?,
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String category;
  final double amount;
  final String description;
  final DateTime expenseDate;
  final String? employeeId;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'category': category,
      'amount': amount,
      'description': description,
      'expenseDate': expenseDate.toIso8601String(),
      if (employeeId != null) 'employeeId': employeeId,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج الموظف (مبسط)
class AppwriteEmployee {
  AppwriteEmployee({
    required this.id,
    required this.name,
    required this.phone,
    required this.position,
    required this.salary,
    required this.status,
    this.terminationDate,
    this.terminationReason,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteEmployee.fromJson(Map<String, dynamic> json) {
    return AppwriteEmployee(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      position: (json['position'] as String?) ?? '',
      salary: ((json['salary'] as num?) ?? 0).toDouble(),
      status: (json['status'] as String?) ?? '',
      terminationDate: json['terminationDate'] as String?,
      terminationReason: json['terminationReason'] as String?,
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String name;
  final String phone;
  final String position;
  final double salary;
  final String status;
  final String? terminationDate;
  final String? terminationReason;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'position': position,
      'salary': salary,
      'status': status,
      if (terminationDate != null) 'terminationDate': terminationDate,
      if (terminationReason != null) 'terminationReason': terminationReason,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج الدين (مبسط)
class AppwriteDebt {
  AppwriteDebt({
    required this.id,
    required this.bookingId,
    required this.guestName,
    required this.amount,
    required this.status,
    required this.dueDate,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteDebt.fromJson(Map<String, dynamic> json) {
    return AppwriteDebt(
      id: (json[r'$id'] as String?) ?? (json['id'] as String?) ?? '',
      bookingId: (json['bookingId'] as String?) ?? '',
      guestName: (json['guestName'] as String?) ?? '',
      amount: ((json['amount'] as num?) ?? 0).toDouble(),
      status: (json['status'] as String?) ?? '',
      dueDate: DateTime.parse((json['dueDate'] as String?) ?? DateTime.now().toIso8601String()),
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified'] as String) : null,
      lastModifiedBy: json['lastModifiedBy'] as String?,
    );
  }
  final String id;
  final String bookingId;
  final String guestName;
  final double amount;
  final String status;
  final DateTime dueDate;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  Map<String, dynamic> toJson() {
    return {
      'bookingId': bookingId,
      'guestName': guestName,
      'amount': amount,
      'status': status,
      'dueDate': dueDate.toIso8601String(),
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}
