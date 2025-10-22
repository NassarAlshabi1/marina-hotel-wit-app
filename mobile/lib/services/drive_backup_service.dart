import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

import 'local_db.dart';

class DriveBackupStatus {
  DriveBackupStatus({
    required this.isSignedIn,
    required this.isBackingUp,
    required this.lastBackup,
    required this.lastError,
    required this.accountEmail,
    required this.pendingReason,
  });

  final bool isSignedIn;
  final bool isBackingUp;
  final DateTime? lastBackup;
  final String? lastError;
  final String? accountEmail;
  final String? pendingReason;

  bool get hasPendingBackup => pendingReason != null;
}

class GoogleDriveBackupService {
  GoogleDriveBackupService(this.db) {
    _accountSub = _googleSignIn.onCurrentUserChanged.listen(_handleAccountChange);
    _googleSignIn.signInSilently().then(_handleAccountChange).catchError((_) {});
    _emit();
  }

  final AppDatabase db;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveAppdataScope, drive.DriveApi.driveFileScope],
  );
  final _controller = StreamController<DriveBackupStatus>.broadcast();
  GoogleSignInAccount? _account;
  GoogleAuthClient? _authClient;
  drive.DriveApi? _drive;
  StreamSubscription<GoogleSignInAccount?>? _accountSub;
  Timer? _pendingTimer;
  String? _pendingReason;
  bool _backingUp = false;
  DateTime? _lastBackup;
  String? _lastError;

  Stream<DriveBackupStatus> get statusStream => _controller.stream;
  bool get isSignedIn => _account != null;

  Future<void> signIn() async {
    try {
      await _googleSignIn.signIn();
    } catch (e) {
      _lastError = e.toString();
      _emit();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingReason = null;
    await _googleSignIn.disconnect();
    await _googleSignIn.signOut();
    await _handleAccountChange(null);
  }

  Future<void> backupNow({String reason = 'manual'}) async {
    if (_drive == null) {
      _lastError = 'لم يتم تسجيل الدخول إلى Google Drive';
      _emit();
      return;
    }
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingReason = null;
    await _performBackup(reason: reason);
  }

  void scheduleAutoBackup(String reason) {
    if (_drive == null) {
      return;
    }
    _pendingReason = reason;
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 12), () {
      _pendingTimer = null;
      final scheduledReason = _pendingReason;
      _pendingReason = null;
      _performBackup(reason: scheduledReason ?? reason);
    });
    _emit();
  }

  Future<Uint8List> buildBackupArchive() => _buildBackupBytes();

  Future<File> exportToDirectory(Directory directory, {String reason = 'manual'}) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final fileName = _backupFileName(reason);
    final file = File('${directory.path}/$fileName');
    final bytes = await _buildBackupBytes();
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> restoreFromArchive(Uint8List data) async {
    try {
      final serializer = driftRuntimeOptions.defaultSerializer;
      final payload = jsonDecode(utf8.decode(gzip.decode(data))) as Map<String, dynamic>;

      final rooms = ((payload['rooms'] as List?) ?? const [])
          .map((row) => serializer.fromJson<Room>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final bookings = ((payload['bookings'] as List?) ?? const [])
          .map((row) => serializer.fromJson<Booking>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final notes = ((payload['booking_notes'] as List?) ?? const [])
          .map((row) => serializer.fromJson<BookingNote>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final employees = ((payload['employees'] as List?) ?? const [])
          .map((row) => serializer.fromJson<Employee>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final expenses = ((payload['expenses'] as List?) ?? const [])
          .map((row) => serializer.fromJson<Expense>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final cashTransactions = ((payload['cash_transactions'] as List?) ?? const [])
          .map((row) => serializer.fromJson<CashTransaction>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final payments = ((payload['payments'] as List?) ?? const [])
          .map((row) => serializer.fromJson<Payment>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final outboxEntries = ((payload['outbox'] as List?) ?? const [])
          .map((row) => serializer.fromJson<OutboxData>(Map<String, dynamic>.from(row as Map)))
          .toList();
      final syncStates = ((payload['sync_state'] as List?) ?? const [])
          .map((row) => serializer.fromJson<SyncStateData>(Map<String, dynamic>.from(row as Map)))
          .toList();

      await db.transaction(() async {
        await db.customStatement('DELETE FROM rooms');
        await db.customStatement('DELETE FROM bookings');
        await db.customStatement('DELETE FROM booking_notes');
        await db.customStatement('DELETE FROM employees');
        await db.customStatement('DELETE FROM expenses');
        await db.customStatement('DELETE FROM cash_transactions');
        await db.customStatement('DELETE FROM payments');
        await db.customStatement('DELETE FROM outbox');
        await db.customStatement('DELETE FROM sync_state');

        if (rooms.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.rooms,
              rooms.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (bookings.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.bookings,
              bookings.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (notes.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.bookingNotes,
              notes.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (employees.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.employees,
              employees.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (expenses.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.expenses,
              expenses.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (cashTransactions.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.cashTransactions,
              cashTransactions.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (payments.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.payments,
              payments.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }
        if (outboxEntries.isNotEmpty) {
          await db.batch((batch) {
            batch.insertAllOnConflictUpdate(
              db.outbox,
              outboxEntries.map((row) => row.toCompanion(true)).toList(),
            );
          });
        }

        final sync = syncStates.isNotEmpty ? syncStates.first : null;
        await db.into(db.syncState).insertOnConflictUpdate(
          SyncStateCompanion(
            id: const Value(1),
            lastServerTs: Value(sync?.lastServerTs ?? 0),
            lastPullTs: Value(sync?.lastPullTs ?? 0),
            lastPushTs: Value(sync?.lastPushTs ?? 0),
            isSyncing: Value(sync?.isSyncing ?? 0),
            version: Value(sync?.version ?? 1),
          ),
        );
      });

      await db.customStatement('VACUUM');
      _lastBackup = DateTime.now();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
      rethrow;
    } finally {
      _emit();
    }
  }

  void dispose() {
    _pendingTimer?.cancel();
    _accountSub?.cancel();
    _authClient?.close();
    _controller.close();
  }

  Future<void> _handleAccountChange(GoogleSignInAccount? account) async {
    _account = account;
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingReason = null;
    _authClient?.close();
    _authClient = null;
    _drive = null;
    _lastError = null;
    if (account != null) {
      try {
        final headers = await account.authHeaders;
        _authClient = GoogleAuthClient(headers);
        _drive = drive.DriveApi(_authClient!);
      } catch (e) {
        _lastError = e.toString();
      }
    }
    _emit();
  }

  Future<void> _performBackup({required String reason}) async {
    if (_drive == null || _backingUp) {
      return;
    }
    _backingUp = true;
    _lastError = null;
    _emit();
    try {
      final bytes = await _buildBackupBytes();
      final fileName = _backupFileName(reason);
      final media = drive.Media(Stream.value(bytes), bytes.length, contentType: 'application/gzip');
      final metadata = drive.File()
        ..name = fileName
        ..parents = ['appDataFolder']
        ..mimeType = 'application/gzip';
      await _drive!.files.create(metadata, uploadMedia: media);
      _lastBackup = DateTime.now();
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _backingUp = false;
      _emit();
    }
  }

  Future<Uint8List> _buildBackupBytes() async {
    final serializer = driftRuntimeOptions.defaultSerializer;
    final rooms = await db.select(db.rooms).get();
    final bookings = await db.select(db.bookings).get();
    final notes = await db.select(db.bookingNotes).get();
    final employees = await db.select(db.employees).get();
    final expenses = await db.select(db.expenses).get();
    final cashTransactions = await db.select(db.cashTransactions).get();
    final payments = await db.select(db.payments).get();
    final outboxEntries = await db.select(db.outbox).get();
    final syncStateRows = await db.select(db.syncState).get();
    final payload = {
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'account_email': _account?.email,
      'rooms': rooms.map((e) => e.toJson(serializer: serializer)).toList(),
      'bookings': bookings.map((e) => e.toJson(serializer: serializer)).toList(),
      'booking_notes': notes.map((e) => e.toJson(serializer: serializer)).toList(),
      'employees': employees.map((e) => e.toJson(serializer: serializer)).toList(),
      'expenses': expenses.map((e) => e.toJson(serializer: serializer)).toList(),
      'cash_transactions': cashTransactions.map((e) => e.toJson(serializer: serializer)).toList(),
      'payments': payments.map((e) => e.toJson(serializer: serializer)).toList(),
      'outbox': outboxEntries.map((e) => e.toJson(serializer: serializer)).toList(),
      'sync_state': syncStateRows.map((e) => e.toJson(serializer: serializer)).toList(),
    };
    final encoded = utf8.encode(jsonEncode(payload));
    final compressed = gzip.encode(encoded);
    return Uint8List.fromList(compressed);
  }

  String _backupFileName(String reason) {
    final sanitized = reason.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').trim();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now().toUtc());
    final suffix = sanitized.isEmpty ? '' : '-$sanitized';
    return 'marina-backup-$stamp$suffix.json.gz';
  }

  void _emit() {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(
      DriveBackupStatus(
        isSignedIn: _account != null,
        isBackingUp: _backingUp,
        lastBackup: _lastBackup,
        lastError: _lastError,
        accountEmail: _account?.email,
        pendingReason: _pendingReason,
      ),
    );
  }
}

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
  }
}
