import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';

import 'local_db.dart';

typedef OnSyncUpdateCallback = void Function(int syncedCount);

class FirestoreShiftNotesService {
  FirestoreShiftNotesService(
    this._database, {
    FirebaseFirestore? firestore,
    this.onSyncUpdate,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final AppDatabase _database;
  final FirebaseFirestore _firestore;
  final OnSyncUpdateCallback? onSyncUpdate;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  bool _isInitialized = false;
  bool _isSyncingLocal = false;
  int _syncedCount = 0;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('shift_notes');

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _subscription = _collection
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen(_handleSnapshot, onError: (error, stackTrace) {
        debugPrint('❌ خطأ في الاستماع لتحديثات Firestore: $error');
        if (stackTrace != null) {
          debugPrint(stackTrace.toString());
        }
      });

      _isInitialized = true;
      await _syncExistingLocalNotes();
      debugPrint('✅ تم تهيئة FirestoreShiftNotesService');
    } catch (e, stackTrace) {
      debugPrint('❌ فشل تهيئة FirestoreShiftNotesService: $e');
      debugPrint(stackTrace.toString());
      rethrow;
    }
  }

  Future<void> _syncExistingLocalNotes() async {
    if (_isSyncingLocal) return;
    _isSyncingLocal = true;

    try {
      final existingNotes = await _database.select(_database.shiftNotes).get();
      for (final note in existingNotes) {
        await upsertNote(note);
      }
    } catch (e) {
      debugPrint('⚠️ تعذر مزامنة الملاحظات المحلية مع Firestore: $e');
    } finally {
      _isSyncingLocal = false;
    }
  }

  Future<void> upsertNote(ShiftNote note) async {
    try {
      final docId = note.id.toString();
      final data = <String, dynamic>{
        'id': note.id,
        'title': note.title,
        'content': note.content,
        'priority': note.priority,
        'shiftType': note.shiftType,
        'isRead': note.isRead == 1,
        'createdAt': _stringToTimestamp(note.createdAt),
        'createdBy': note.createdBy,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (note.expiresAt != null) {
        data['expiresAt'] = _stringToTimestamp(note.expiresAt!);
      }

      await _collection.doc(docId).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('⚠️ تعذر مزامنة الملاحظة مع Firestore: $e');
    }
  }

  Future<void> deleteNote(int id) async {
    try {
      await _collection.doc(id.toString()).delete();
    } catch (e) {
      debugPrint('⚠️ تعذر حذف الملاحظة من Firestore: $e');
    }
  }

  Future<void> _handleSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    _syncedCount = snapshot.docs.length;
    onSyncUpdate?.call(_syncedCount);

    for (final change in snapshot.docChanges) {
      final data = change.doc.data();
      if (data == null) continue;

      final id = _readId(change.doc.id, data);
      if (id == null) continue;

      switch (change.type) {
        case DocumentChangeType.added:
        case DocumentChangeType.modified:
          await _upsertLocalNote(id, data);
          break;
        case DocumentChangeType.removed:
          await (_database.delete(_database.shiftNotes)
                ..where((tbl) => tbl.id.equals(id)))
              .go();
          break;
      }
    }
  }

  Future<void> _upsertLocalNote(int id, Map<String, dynamic> data) async {
    final createdAt = _timestampToString(data['createdAt']) ??
        DateTime.now().toIso8601String();
    final expiresAt = _timestampToString(data['expiresAt']);
    final isRead = data['isRead'] == true ? 1 : 0;

    final companion = ShiftNotesCompanion(
      id: drift.Value(id),
      title: drift.Value(data['title'] as String? ?? ''),
      content: drift.Value(data['content'] as String? ?? ''),
      priority: drift.Value(data['priority'] as String? ?? 'medium'),
      shiftType: drift.Value(data['shiftType'] as String? ?? 'all'),
      isRead: drift.Value(isRead),
      createdAt: drift.Value(createdAt),
      expiresAt:
          expiresAt != null ? drift.Value(expiresAt) : const drift.Value.absent(),
      createdBy: drift.Value(data['createdBy'] as String? ?? 'user'),
    );

    await _database.into(_database.shiftNotes).insert(
          companion,
          mode: drift.InsertMode.insertOrReplace,
        );
  }

  Timestamp _stringToTimestamp(String value) {
    final parsed = DateTime.tryParse(value);
    return Timestamp.fromDate(parsed ?? DateTime.now());
  }

  String? _timestampToString(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) {
      return value.toDate().toIso8601String();
    }
    if (value is DateTime) {
      return value.toIso8601String();
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toIso8601String();
    }
    return null;
  }

  int? _readId(String docId, Map<String, dynamic> data) {
    final rawId = data['id'];
    if (rawId is int) return rawId;
    if (rawId is String) return int.tryParse(rawId);
    return int.tryParse(docId);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
