/// ============================================================
/// Marina Hotel - Mock Appwrite Service
/// ============================================================
/// Mock لـ AppwriteService للاختبارات الوحدوية والتكاملية
/// يمكن محاكاة: نجاح/فشل العمليات، تأخير الشبكة، سيناريوهات المزامنة
/// ============================================================

import 'dart:async';

import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:appwrite/models.dart' as models;
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:marina_hotel_mobile/services/appwrite_service.dart';
import 'package:marina_hotel_mobile/services/appwrite_config.dart';

/// Mock لـ AppwriteService مع بيانات وهمية قابلة للتخصيص
class MockAppwriteService extends Mock implements AppwriteService {
  final Map<String, List<Map<String, dynamic>>> _mockCollections = {};
  bool _shouldFail = false;
  Duration _simulatedDelay = Duration.zero;
  int _callCount = 0;

  /// تعيين بيانات وهمية لمجموعة
  void seedCollection(String collectionId, List<Map<String, dynamic>> documents) {
    _mockCollections[collectionId] = documents;
  }

  /// تعيين تأخير محاكاة الشبكة
  void setSimulatedDelay(Duration delay) {
    _simulatedDelay = delay;
  }

  /// تعيين فشل العمليات
  void setShouldFail(bool fail) {
    _shouldFail = fail;
  }

  /// عدد مرات استدعاء الـ API
  int get callCount => _callCount;

  @override
  Future<List<models.Document>> listDocuments({
    required String collectionId,
    List<String>? queries,
    bool useCache = true,
  }) async {
    _callCount++;
    if (_simulatedDelay > Duration.zero) {
      await Future.delayed(_simulatedDelay);
    }
    if (_shouldFail) throw Exception('Simulated failure');

    final docs = _mockCollections[collectionId] ?? [];
    return docs.map((data) => models.Document(
      $id: data['localUuid'] as String? ?? 'mock_${_callCount}',
      $collectionId: collectionId,
      $databaseId: AppwriteConfigManager.databaseId,
      $createdAt: DateTime.now().toIso8601String(),
      $updatedAt: DateTime.now().toIso8601String(),
      $permissions: [],
      data: data,
    )).toList();
  }

  @override
  Future<List<models.Document>> listRooms({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.roomsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<List<models.Document>> listBookings({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.bookingsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<List<models.Document>> listEmployees({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.employeesCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<List<models.Document>> listPayments({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.paymentsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<List<models.Document>> listExpenses({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.expensesCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<List<models.Document>> listDebts({
    List<String>? queries,
    bool useCache = true,
  }) {
    return listDocuments(
      collectionId: AppwriteConfig.debtsCollectionId,
      queries: queries,
      useCache: useCache,
    );
  }

  @override
  Future<models.Document?> getDocumentSafe({
    required String collectionId,
    required String documentId,
  }) async {
    _callCount++;
    if (_simulatedDelay > Duration.zero) {
      await Future.delayed(_simulatedDelay);
    }
    if (_shouldFail) throw Exception('Simulated failure');

    final docs = _mockCollections[collectionId] ?? [];
    final doc = docs.where((d) => d['localUuid'] == documentId).toList();
    if (doc.isEmpty) return null;

    return models.Document(
      $id: documentId,
      $collectionId: collectionId,
      $databaseId: AppwriteConfigManager.databaseId,
      $createdAt: DateTime.now().toIso8601String(),
      $updatedAt: DateTime.now().toIso8601String(),
      $permissions: [],
      data: doc.first,
    );
  }

  @override
  Future<models.Document> createDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _callCount++;
    if (_shouldFail) throw Exception('Simulated failure');

    _mockCollections.putIfAbsent(collectionId, () => []);
    _mockCollections[collectionId]!.add({...data, 'localUuid': documentId});

    return models.Document(
      $id: documentId,
      $collectionId: collectionId,
      $databaseId: AppwriteConfigManager.databaseId,
      $createdAt: DateTime.now().toIso8601String(),
      $updatedAt: DateTime.now().toIso8601String(),
      $permissions: [],
      data: data,
    );
  }

  @override
  Future<models.Document> updateDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    _callCount++;
    if (_shouldFail) throw Exception('Simulated failure');

    return models.Document(
      $id: documentId,
      $collectionId: collectionId,
      $databaseId: AppwriteConfigManager.databaseId,
      $createdAt: DateTime.now().toIso8601String(),
      $updatedAt: DateTime.now().toIso8601String(),
      $permissions: [],
      data: data,
    );
  }

  @override
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    _callCount++;
    if (_shouldFail) throw Exception('Simulated failure');

    _mockCollections[collectionId]?.removeWhere((d) => d['localUuid'] == documentId);
  }

  // إضافة الدوال الأخرى حسب الحاجة...
  @override
  Future<bool> testConnection() async => !_shouldFail;

  @override
  Future<void> initialize() async {}
}
