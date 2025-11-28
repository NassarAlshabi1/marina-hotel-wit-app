// نماذج البيانات لـ Appwrite

/// نموذج الجهاز المسجل
class AppwriteDevice {
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

  AppwriteDevice({
    required this.id,
    required this.deviceName,
    required this.deviceModel,
    required this.osVersion,
    required this.lastSeen,
    this.lastActive,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.version,
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
      id: json['\$id'] ?? json['id'] ?? '',
      deviceName: json['deviceName'] ?? '',
      deviceModel: json['deviceModel'] ?? '',
      osVersion: json['osVersion'] ?? '',
      lastSeen: parseDate(json['lastSeen'], fallback: DateTime.now()),
      lastActive: json.containsKey('lastActive') ? parseDate(json['lastActive']) : null,
      status: json['status'] ?? 'active',
      createdAt: parseDate(json['createdAt'], fallback: DateTime.now()),
      updatedAt: parseDate(json['updatedAt'], fallback: DateTime.now()),
      version: (json['version'] is num) ? (json['version'] as num).toInt() : int.tryParse('${json['version'] ?? 1}') ?? 1,
      origin: json['origin']?.toString(),
      localUuid: json['localUuid']?.toString(),
    );
  }

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

  AppwriteSyncLog({
    required this.id,
    required this.deviceId,
    required this.syncType,
    required this.startTime,
    this.endTime,
    required this.status,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
    this.details,
  });

  factory AppwriteSyncLog.fromJson(Map<String, dynamic> json) {
    return AppwriteSyncLog(
      id: json['\$id'] ?? json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      syncType: json['syncType'] ?? 'full',
      startTime: DateTime.parse(json['startTime'] ?? DateTime.now().toIso8601String()),
      endTime: json['endTime'] != null ? DateTime.parse(json['endTime']) : null,
      status: json['status'] ?? 'in_progress',
      recordsPushed: json['recordsPushed'] ?? 0,
      recordsPulled: json['recordsPulled'] ?? 0,
      conflicts: json['conflicts'] ?? 0,
      errorMessage: json['errorMessage'],
      details: json['details'],
    );
  }

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
  final String id;
  final String roomNumber;
  final String type;
  final String status;
  final double price;
  final int floor;
  final DateTime? lastModified;
  final String? lastModifiedBy;

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
      id: json['\$id'] ?? json['id'] ?? '',
      roomNumber: json['roomNumber'] ?? '',
      type: json['type'] ?? '',
      status: json['status'] ?? '',
      price: (json['price'] ?? 0).toDouble(),
      floor: json['floor'] ?? 0,
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

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
      id: json['\$id'] ?? json['id'] ?? '',
      roomId: json['roomId'] ?? '',
      guestName: json['guestName'] ?? '',
      guestPhone: json['guestPhone'] ?? '',
      checkIn: DateTime.parse(json['checkIn'] ?? DateTime.now().toIso8601String()),
      checkOut: DateTime.parse(json['checkOut'] ?? DateTime.now().toIso8601String()),
      status: json['status'] ?? '',
      totalAmount: (json['totalAmount'] ?? 0).toDouble(),
      paidAmount: (json['paidAmount'] ?? 0).toDouble(),
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

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
  final String id;
  final String bookingId;
  final double amount;
  final String paymentMethod;
  final DateTime paymentDate;
  final String? notes;
  final DateTime? lastModified;
  final String? lastModifiedBy;

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
      id: json['\$id'] ?? json['id'] ?? '',
      bookingId: json['bookingId'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      paymentMethod: json['paymentMethod'] ?? '',
      paymentDate: DateTime.parse(json['paymentDate'] ?? DateTime.now().toIso8601String()),
      notes: json['notes'],
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

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
  final String id;
  final String category;
  final double amount;
  final String description;
  final DateTime expenseDate;
  final String? employeeId;
  final DateTime? lastModified;
  final String? lastModifiedBy;

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
      id: json['\$id'] ?? json['id'] ?? '',
      category: json['category'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      description: json['description'] ?? '',
      expenseDate: DateTime.parse(json['expenseDate'] ?? DateTime.now().toIso8601String()),
      employeeId: json['employeeId'],
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

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
  final String id;
  final String name;
  final String phone;
  final String position;
  final double salary;
  final String status;
  final DateTime? lastModified;
  final String? lastModifiedBy;

  AppwriteEmployee({
    required this.id,
    required this.name,
    required this.phone,
    required this.position,
    required this.salary,
    required this.status,
    this.lastModified,
    this.lastModifiedBy,
  });

  factory AppwriteEmployee.fromJson(Map<String, dynamic> json) {
    return AppwriteEmployee(
      id: json['\$id'] ?? json['id'] ?? '',
      name: json['name'] ?? '',
      phone: json['phone'] ?? '',
      position: json['position'] ?? '',
      salary: (json['salary'] ?? 0).toDouble(),
      status: json['status'] ?? '',
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'phone': phone,
      'position': position,
      'salary': salary,
      'status': status,
      if (lastModified != null) 'lastModified': lastModified!.toIso8601String(),
      if (lastModifiedBy != null) 'lastModifiedBy': lastModifiedBy,
    };
  }
}

/// نموذج الدين (مبسط)
class AppwriteDebt {
  final String id;
  final String bookingId;
  final String guestName;
  final double amount;
  final String status;
  final DateTime dueDate;
  final DateTime? lastModified;
  final String? lastModifiedBy;

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
      id: json['\$id'] ?? json['id'] ?? '',
      bookingId: json['bookingId'] ?? '',
      guestName: json['guestName'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status'] ?? '',
      dueDate: DateTime.parse(json['dueDate'] ?? DateTime.now().toIso8601String()),
      lastModified: json['lastModified'] != null 
        ? DateTime.parse(json['lastModified']) 
        : null,
      lastModifiedBy: json['lastModifiedBy'],
    );
  }

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
