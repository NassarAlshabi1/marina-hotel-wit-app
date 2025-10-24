import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/local_db.dart';
import '../services/drive_service.dart';

class DriveBackupService {
  final AppDatabase db;
  final DriveService driveService;

  DriveBackupService(this.db, this.driveService);

  static const String _appName = 'Marina Hotel';
  static const String _backupFolderName = '$_appName - Backups';

  Future<String?> getOrCreateBackupFolder() async {
    await driveService.initialize();
    final files = await driveService.listFiles();
    String? folderId;

    for (final file in files.files ?? []) {
      if (file.name == _backupFolderName && file.mimeType == 'application/vnd.google-apps.folder') {
        folderId = file.id;
        break;
      }
    }

    if (folderId == null) {
      final folder = drive.File()
        ..name = _backupFolderName
        ..mimeType = 'application/vnd.google-apps.folder';
      final createdFolder = await driveService._driveApi!.files.create(folder);
      folderId = createdFolder.id;
    }

    return folderId;
  }

  Future<Map<String, dynamic>> _serializeDatabase() async {
    final backupData = <String, dynamic>{};

    // Serialize Rooms
    final rooms = await db.select(db.rooms).get();
    backupData['rooms'] = rooms.map((r) => r.toJson()).toList();

    // Serialize Bookings
    final bookings = await db.select(db.bookings).get();
    backupData['bookings'] = bookings.map((b) => b.toJson()).toList();

    // Serialize BookingNotes
    final bookingNotes = await db.select(db.bookingNotes).get();
    backupData['bookingNotes'] = bookingNotes.map((bn) => bn.toJson()).toList();

    // Serialize Employees
    final employees = await db.select(db.employees).get();
    backupData['employees'] = employees.map((e) => e.toJson()).toList();

    // Serialize Expenses
    final expenses = await db.select(db.expenses).get();
    backupData['expenses'] = expenses.map((ex) => ex.toJson()).toList();

    // Serialize CashTransactions
    final cashTransactions = await db.select(db.cashTransactions).get();
    backupData['cashTransactions'] = cashTransactions.map((ct) => ct.toJson()).toList();

    // Serialize Payments
    final payments = await db.select(db.payments).get();
    backupData['payments'] = payments.map((p) => p.toJson()).toList();

    // Serialize Outbox (for pending sync)
    final outbox = await db.select(db.outbox).get();
    backupData['outbox'] = outbox.map((o) => o.toJson()).toList();

    // Serialize SyncState
    final syncState = await db.select(db.syncState).getSingleOrNull();
    if (syncState != null) {
      backupData['syncState'] = syncState.toJson();
    }

    // Add metadata
    backupData['metadata'] = {
      'backupDate': DateTime.now().toIso8601String(),
      'appVersion': '1.0.0', // Update with actual version
      'dbSchemaVersion': db.schemaVersion,
    };

    return backupData;
  }

  Future<bool> backup() async {
    try {
      final folderId = await getOrCreateBackupFolder();
      if (folderId == null) return false;

      final data = await _serializeDatabase();
      final jsonString = json.encode(data);
      final bytes = utf8.encode(jsonString);

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '').split('.')[0];
      final fileName = 'backup_$timestamp.json';

      await driveService.uploadFile(fileName, bytes, folderId: folderId);

      // Update local last backup time (could add a local table for this)
      debugPrint('Backup successful: $fileName in folder $folderId');
      return true;
    } catch (e) {
      debugPrint('Backup failed: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> listBackups() async {
    try {
      final folderId = await getOrCreateBackupFolder();
      if (folderId == null) return [];

      final files = await driveService.listFiles(folderId: folderId);
      return (files.files ?? [])
          .where((f) => f.name!.endsWith('.json'))
          .map((f) => {
                'id': f.id,
                'name': f.name,
                'size': f.size,
                'modifiedTime': f.modifiedTime?.toIso8601String(),
              })
          .toList();
    } catch (e) {
      debugPrint('List backups failed: $e');
      return [];
    }
  }

  Future<bool> restore(String fileId) async {
    try {
      final bytes = await driveService.downloadFile(fileId);
      final jsonString = utf8.decode(bytes);
      final data = json.decode(jsonString) as Map<String, dynamic>;

      // Clear existing data (backup current if needed, but for simplicity, clear)
      await db.transaction(() async {
        await db.delete(db.rooms).go();
        await db.delete(db.bookings).go();
        await db.delete(db.bookingNotes).go();
        await db.delete(db.employees).go();
        await db.delete(db.expenses).go();
        await db.delete(db.cashTransactions).go();
        await db.delete(db.payments).go();
        await db.delete(db.outbox).go();
        if (data.containsKey('syncState')) {
          await db.delete(db.syncState).go();
        }
      });

      // Insert restored data
      await db.transaction(() async {
        // Restore Rooms
        if (data['rooms'] is List) {
          for (final roomJson in data['rooms']) {
            await db.into(db.rooms).insert(Room.fromJson(roomJson));
          }
        }

        // Restore Bookings
        if (data['bookings'] is List) {
          for (final bookingJson in data['bookings']) {
            await db.into(db.bookings).insert(Booking.fromJson(bookingJson));
          }
        }

        // Restore other tables similarly...
        if (data['bookingNotes'] is List) {
          for (final noteJson in data['bookingNotes']) {
            await db.into(db.bookingNotes).insert(BookingNote.fromJson(noteJson));
          }
        }

        if (data['employees'] is List) {
          for (final empJson in data['employees']) {
            await db.into(db.employees).insert(Employee.fromJson(empJson));
          }
        }

        if (data['expenses'] is List) {
          for (final expJson in data['expenses']) {
            await db.into(db.expenses).insert(Expense.fromJson(expJson));
          }
        }

        if (data['cashTransactions'] is List) {
          for (final ctJson in data['cashTransactions']) {
            await db.into(db.cashTransactions).insert(CashTransaction.fromJson(ctJson));
          }
        }

        if (data['payments'] is List) {
          for (final payJson in data['payments']) {
            await db.into(db.payments).insert(Payment.fromJson(payJson));
          }
        }

        if (data['outbox'] is List) {
          for (final outJson in data['outbox']) {
            await db.into(db.outbox).insert(OutboxRow.fromJson(outJson));
          }
        }

        if (data['syncState'] != null) {
          await db.into(db.syncState).insert(SyncStateCompanion.insert(
            lastServerTs: Value(data['syncState']['lastServerTs'] ?? 0),
            lastPullTs: Value(data['syncState']['lastPullTs'] ?? 0),
            lastPushTs: Value(data['syncState']['lastPushTs'] ?? 0),
            isSyncing: Value(data['syncState']['isSyncing'] ?? 0),
            version: Value(data['syncState']['version'] ?? 1),
          ));
        }
      });

      debugPrint('Restore successful from $fileId');
      return true;
    } catch (e) {
      debugPrint('Restore failed: $e');
      return false;
    }
  }
}

// Extension for JSON serialization (add to each model if not present)
extension RoomJson on Room {
  Map<String, dynamic> toJson() => {
    'id': id,
    'roomNumber': roomNumber,
    'type': type,
    'price': price,
    'status': status,
    'imageUrl': imageUrl,
    'localUuid': localUuid,
    'serverId': serverId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'deletedAt': deletedAt,
    'lastModified': lastModified,
    'version': version,
    'origin': origin,
  };

  static Room fromJson(Map<String, dynamic> json) => Room(
    id: json['id'],
    roomNumber: json['roomNumber'],
    type: json['type'],
    price: json['price'],
    status: json['status'],
    imageUrl: json['imageUrl'],
    localUuid: json['localUuid'],
    serverId: json['serverId'],
    createdAt: json['createdAt'],
    updatedAt: json['updatedAt'],
    deletedAt: json['deletedAt'],
    lastModified: json['lastModified'],
    version: json['version'],
    origin: json['origin'],
  );
}

// Similar extensions for other tables... (abbreviated for brevity)