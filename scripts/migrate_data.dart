// ============================================================================
// Marina Hotel - Data Migration Script
// سكريبت نقل البيانات من PocketBase إلى Supabase
// Migrate data from PocketBase to Supabase
// ============================================================================

import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

// ============================================================================
// التكوين | Configuration
// ============================================================================

class MigrationConfig {
  // PocketBase Configuration
  static const String pocketbaseUrl = 'http://localhost:8090'; // عدّل هذا
  static const String pocketbaseEmail = 'admin@example.com'; // عدّل هذا
  static const String pocketbasePassword = 'your_password'; // عدّل هذا

  // Supabase Configuration
  static const String supabaseUrl = 'https://YOUR_PROJECT_ID.supabase.co'; // عدّل هذا
  static const String supabaseServiceKey = 'YOUR_SERVICE_ROLE_KEY'; // عدّل هذا

  // Migration Settings
  static const int batchSize = 100;
  static const bool dryRun = false; // true = لا ترفع البيانات، اختبار فقط
  static const bool verbose = true; // true = طباعة تفاصيل أكثر
}

// ============================================================================
// الدوال المساعدة | Helper Functions
// ============================================================================

/// طباعة رسالة ملونة | Print colored message
void printInfo(String message) {
  print('\x1B[34mℹ️  $message\x1B[0m');
}

void printSuccess(String message) {
  print('\x1B[32m✅ $message\x1B[0m');
}

void printWarning(String message) {
  print('\x1B[33m⚠️  $message\x1B[0m');
}

void printError(String message) {
  print('\x1B[31m❌ $message\x1B[0m');
}

/// تحويل UUID من string إلى UUID format
String ensureUuid(String? uuid) {
  if (uuid == null || uuid.isEmpty) {
    return _generateUuid();
  }

  // التحقق من format
  final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false);

  if (uuidPattern.hasMatch(uuid)) {
    return uuid;
  }

  // إذا كان UUID بدون شرطات، أضف الشرطات
  if (uuid.length == 32) {
    return '${uuid.substring(0, 8)}-${uuid.substring(8, 12)}-${uuid.substring(12, 16)}-${uuid.substring(16, 20)}-${uuid.substring(20)}';
  }

  // إذا فشل كل شيء، أنشئ UUID جديد
  return _generateUuid();
}

/// إنشاء UUID جديد
String _generateUuid() {
  // UUID v4 simple generator
  final random = DateTime.now().millisecondsSinceEpoch.toString() +
      (DateTime.now().microsecond * 1000).toString();
  return '${random.substring(0, 8)}-${random.substring(8, 12)}-4${random.substring(13, 16)}-${random.substring(16, 20)}-${random.substring(20, 32)}';
}

/// تحويل timestamp من integer إلى ISO string
String timestampToIso(dynamic timestamp) {
  if (timestamp == null) return DateTime.now().toIso8601String();

  try {
    if (timestamp is int) {
      // Epoch timestamp (seconds)
      return DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
          .toIso8601String();
    } else if (timestamp is String) {
      // Already ISO string
      return timestamp;
    }
  } catch (e) {
    printWarning('Failed to convert timestamp: $timestamp');
  }

  return DateTime.now().toIso8601String();
}

// ============================================================================
// PocketBase Client
// ============================================================================

class PocketBaseClient {
  final String baseUrl;
  String? authToken;

  PocketBaseClient(this.baseUrl);

  /// تسجيل الدخول
  Future<void> authenticate(String email, String password) async {
    printInfo('Authenticating with PocketBase...');

    final response = await http.post(
      Uri.parse('$baseUrl/api/admins/auth-with-password'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identity': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      authToken = data['token'];
      printSuccess('Authenticated with PocketBase');
    } else {
      throw Exception('Failed to authenticate: ${response.body}');
    }
  }

  /// الحصول على جميع السجلات من collection
  Future<List<Map<String, dynamic>>> getAll(String collection) async {
    printInfo('Fetching all records from $collection...');

    final List<Map<String, dynamic>> allRecords = [];
    int page = 1;
    int perPage = 500;
    bool hasMore = true;

    while (hasMore) {
      final response = await http.get(
        Uri.parse(
            '$baseUrl/api/collections/$collection/records?page=$page&perPage=$perPage'),
        headers: {'Authorization': authToken ?? ''},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);

        allRecords.addAll(items);

        hasMore = items.length == perPage;
        page++;

        if (MigrationConfig.verbose) {
          printInfo('  Fetched ${items.length} records (total: ${allRecords.length})');
        }
      } else {
        throw Exception(
            'Failed to fetch $collection: ${response.statusCode} ${response.body}');
      }
    }

    printSuccess('Fetched ${allRecords.length} records from $collection');
    return allRecords;
  }
}

// ============================================================================
// Supabase Client
// ============================================================================

class SupabaseClient {
  final String baseUrl;
  final String serviceKey;

  SupabaseClient(this.baseUrl, this.serviceKey);

  /// إدراج سجلات في جدول
  Future<void> insertBatch(
      String table, List<Map<String, dynamic>> records) async {
    if (records.isEmpty) return;

    printInfo('Inserting ${records.length} records into $table...');

    if (MigrationConfig.dryRun) {
      printWarning('DRY RUN: Would insert ${records.length} records');
      return;
    }

    final response = await http.post(
      Uri.parse('$baseUrl/rest/v1/$table'),
      headers: {
        'Authorization': 'Bearer $serviceKey',
        'apikey': serviceKey,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(records),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      printSuccess('Inserted ${records.length} records into $table');
    } else {
      throw Exception(
          'Failed to insert into $table: ${response.statusCode} ${response.body}');
    }
  }

  /// حذف جميع السجلات من جدول (للاختبار فقط)
  Future<void> truncateTable(String table) async {
    printWarning('Truncating table $table...');

    if (MigrationConfig.dryRun) {
      printWarning('DRY RUN: Would truncate table $table');
      return;
    }

    final response = await http.delete(
      Uri.parse('$baseUrl/rest/v1/$table?id=neq.0'),
      headers: {
        'Authorization': 'Bearer $serviceKey',
        'apikey': serviceKey,
      },
    );

    if (response.statusCode == 200 || response.statusCode == 204) {
      printSuccess('Truncated table $table');
    } else {
      printWarning('Failed to truncate $table: ${response.statusCode}');
    }
  }
}

// ============================================================================
// Data Transformers - محولات البيانات
// ============================================================================

/// تحويل بيانات الغرف
List<Map<String, dynamic>> transformRooms(List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'room_number': r['room_number'],
      'type': r['type'] ?? '',
      'price': (r['price'] ?? 0).toDouble(),
      'status': r['status'] ?? 'شاغرة',
      'image_url': r['image_url'],
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at': r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات الحجوزات
List<Map<String, dynamic>> transformBookings(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'server_booking_id': r['server_booking_id'],
      'room_number': r['room_number'],
      'guest_name': r['guest_name'] ?? '',
      'guest_phone': r['guest_phone'] ?? '',
      'guest_id_type': r['guest_id_type'] ?? 'بطاقة شخصية',
      'guest_id_number': r['guest_id_number'] ?? '',
      'guest_id_issue_date': r['guest_id_issue_date'],
      'guest_id_issue_place': r['guest_id_issue_place'],
      'guest_nationality': r['guest_nationality'] ?? '',
      'guest_email': r['guest_email'],
      'guest_address': r['guest_address'],
      'checkin_date': timestampToIso(r['checkin_date']),
      'checkout_date':
          r['checkout_date'] != null ? timestampToIso(r['checkout_date']) : null,
      'actual_checkout': r['actual_checkout'] != null
          ? timestampToIso(r['actual_checkout'])
          : null,
      'status': r['status'] ?? 'محجوزة',
      'notes': r['notes'],
      'expected_nights': r['expected_nights'] ?? 1,
      'calculated_nights': r['calculated_nights'] ?? 1,
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات ملاحظات الحجوزات
List<Map<String, dynamic>> transformBookingNotes(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'booking_id': r['booking_id'],
      'note_text': r['note_text'] ?? '',
      'alert_type': r['alert_type'] ?? 'low',
      'alert_until':
          r['alert_until'] != null ? timestampToIso(r['alert_until']) : null,
      'is_active': r['is_active'] ?? 1,
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات الموظفين
List<Map<String, dynamic>> transformEmployees(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'name': r['name'] ?? '',
      'basic_salary': (r['basic_salary'] ?? 0).toDouble(),
      'position': r['position'] ?? 'موظف',
      'phone': r['phone'] ?? '',
      'hire_date': r['hire_date'] ?? '',
      'status': r['status'] ?? 'active',
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات المصروفات
List<Map<String, dynamic>> transformExpenses(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'expense_type': r['expense_type'] ?? 'other',
      'related_id': r['related_id'],
      'description': r['description'] ?? '',
      'amount': (r['amount'] ?? 0).toDouble(),
      'date': r['date'] ?? DateTime.now().toIso8601String().split('T')[0],
      'cash_transaction_id': r['cash_transaction_id'],
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات المعاملات النقدية
List<Map<String, dynamic>> transformCashTransactions(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'register_id': r['register_id'],
      'transaction_type': r['transaction_type'] ?? 'income',
      'amount': (r['amount'] ?? 0).toDouble(),
      'reference_type': r['reference_type'],
      'reference_id': r['reference_id'],
      'description': r['description'],
      'transaction_time': timestampToIso(r['transaction_time']),
      'created_by': r['created_by'],
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات الدفعات
List<Map<String, dynamic>> transformPayments(
    List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'server_payment_id': r['server_payment_id'],
      'booking_local_id': r['booking_local_id'],
      'server_booking_id': r['server_booking_id'],
      'room_number': r['room_number'],
      'amount': (r['amount'] ?? 0).toDouble(),
      'payment_date': timestampToIso(r['payment_date']),
      'notes': r['notes'],
      'payment_method': r['payment_method'] ?? 'نقدي',
      'revenue_type': r['revenue_type'] ?? 'room',
      'cash_transaction_local_id': r['cash_transaction_local_id'],
      'cash_transaction_server_id': r['cash_transaction_server_id'],
      'reference_number': r['reference_number'],
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

/// تحويل بيانات الديون
List<Map<String, dynamic>> transformDebts(List<Map<String, dynamic>> records) {
  return records.map((r) {
    return {
      'booking_local_id': r['booking_local_id'],
      'guest_name': r['guest_name'] ?? '',
      'checkin_date': r['checkin_date'] ?? '',
      'checkout_date': r['checkout_date'] ?? '',
      'date_recorded': r['date_recorded'] ?? '',
      'debt_reason': r['debt_reason'] ?? '',
      'total_amount': (r['total_amount'] ?? 0).toDouble(),
      'paid_amount': (r['paid_amount'] ?? 0).toDouble(),
      'remaining_amount': (r['remaining_amount'] ?? 0).toDouble(),
      'payment_date': r['payment_date'] ?? '',
      'is_settled': r['is_settled'] ?? 0,
      'pledge': r['pledge'],
      'pledge_type': r['pledge_type'],
      'note': r['note'],
      'local_uuid': ensureUuid(r['local_uuid']),
      'server_id': r['server_id'],
      'created_at': timestampToIso(r['created_at']),
      'updated_at': timestampToIso(r['updated_at']),
      'deleted_at':
          r['deleted_at'] != null ? timestampToIso(r['deleted_at']) : null,
      'last_modified': timestampToIso(r['last_modified']),
      'version': r['version'] ?? 1,
      'origin': r['origin'] ?? 'local',
    };
  }).toList();
}

// ============================================================================
// Main Migration Function
// ============================================================================

Future<void> main() async {
  print('');
  print('═══════════════════════════════════════════════════════');
  print('   Marina Hotel - Data Migration Script');
  print('   From PocketBase to Supabase');
  print('═══════════════════════════════════════════════════════');
  print('');

  if (MigrationConfig.dryRun) {
    printWarning('DRY RUN MODE: No data will be inserted');
  }

  try {
    // إنشاء العملاء
    final pb = PocketBaseClient(MigrationConfig.pocketbaseUrl);
    final sb = SupabaseClient(
        MigrationConfig.supabaseUrl, MigrationConfig.supabaseServiceKey);

    // تسجيل الدخول إلى PocketBase
    await pb.authenticate(
        MigrationConfig.pocketbaseEmail, MigrationConfig.pocketbasePassword);

    // إحصائيات
    final stats = <String, int>{};

    // قائمة الجداول للنقل (بالترتيب الصحيح للـ Foreign Keys)
    final migrations = [
      {
        'pb_collection': 'rooms',
        'sb_table': 'rooms',
        'transform': transformRooms
      },
      {
        'pb_collection': 'employees',
        'sb_table': 'employees',
        'transform': transformEmployees
      },
      {
        'pb_collection': 'bookings',
        'sb_table': 'bookings',
        'transform': transformBookings
      },
      {
        'pb_collection': 'booking_notes',
        'sb_table': 'booking_notes',
        'transform': transformBookingNotes
      },
      {
        'pb_collection': 'cash_transactions',
        'sb_table': 'cash_transactions',
        'transform': transformCashTransactions
      },
      {
        'pb_collection': 'expenses',
        'sb_table': 'expenses',
        'transform': transformExpenses
      },
      {
        'pb_collection': 'payments',
        'sb_table': 'payments',
        'transform': transformPayments
      },
      {
        'pb_collection': 'debts',
        'sb_table': 'debts',
        'transform': transformDebts
      },
    ];

    // تنفيذ النقل لكل جدول
    for (final migration in migrations) {
      final pbCollection = migration['pb_collection'] as String;
      final sbTable = migration['sb_table'] as String;
      final transform = migration['transform']
          as List<Map<String, dynamic>> Function(List<Map<String, dynamic>>);

      print('');
      printInfo('──────────────────────────────────────────');
      printInfo('Migrating $pbCollection → $sbTable');
      printInfo('──────────────────────────────────────────');

      try {
        // جلب البيانات من PocketBase
        final pbRecords = await pb.getAll(pbCollection);

        if (pbRecords.isEmpty) {
          printWarning('No records found in $pbCollection');
          stats[sbTable] = 0;
          continue;
        }

        // تحويل البيانات
        final sbRecords = transform(pbRecords);

        // رفع البيانات إلى Supabase (بدفعات)
        final batchSize = MigrationConfig.batchSize;
        for (int i = 0; i < sbRecords.length; i += batchSize) {
          final end = (i + batchSize < sbRecords.length)
              ? i + batchSize
              : sbRecords.length;
          final batch = sbRecords.sublist(i, end);

          await sb.insertBatch(sbTable, batch);
        }

        stats[sbTable] = sbRecords.length;
        printSuccess('✓ Migrated ${sbRecords.length} records');
      } catch (e) {
        printError('Failed to migrate $pbCollection: $e');
        stats[sbTable] = -1;
      }
    }

    // طباعة التقرير النهائي
    print('');
    print('═══════════════════════════════════════════════════════');
    print('   Migration Summary');
    print('═══════════════════════════════════════════════════════');
    print('');

    int totalSuccess = 0;
    int totalFailed = 0;

    stats.forEach((table, count) {
      if (count >= 0) {
        printSuccess('$table: $count records');
        totalSuccess += count;
      } else {
        printError('$table: FAILED');
        totalFailed++;
      }
    });

    print('');
    print('───────────────────────────────────────────────────────');
    printInfo('Total records migrated: $totalSuccess');
    if (totalFailed > 0) {
      printError('Failed tables: $totalFailed');
    }
    print('═══════════════════════════════════════════════════════');
    print('');

    if (totalFailed == 0) {
      printSuccess('🎉 Migration completed successfully!');
    } else {
      printWarning('⚠️  Migration completed with errors');
    }
  } catch (e, stackTrace) {
    printError('Migration failed: $e');
    if (MigrationConfig.verbose) {
      print(stackTrace);
    }
    exit(1);
  }
}
