import 'package:appwrite/models.dart' as models;
import '../services/local_db.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_config.dart';
import '../services/appwrite_error_handler.dart';
import '../services/advanced_query_builder.dart';

/// Repository Pattern للغرف
///
/// يوفر واجهة موحدة للتعامل مع بيانات الغرف
/// يخفي تفاصيل التنفيذ (Appwrite/Local DB)
abstract class RoomRepository {
  Future<Room?> getById(String id);
  Future<List<Room>> getAll();
  Future<Room> create(Room room);
  Future<Room> update(String id, Room room);
  Future<void> delete(String id);
  Future<List<Room>> search(String query);
  Future<List<Room>> getAvailable();
  Future<List<Room>> getByPriceRange(double min, double max);
  Future<List<Room>> getPaginated({int limit = 25, int offset = 0});
}

/// تنفيذ Repository باستخدام Appwrite
class AppwriteRoomRepository implements RoomRepository {
  AppwriteRoomRepository({
    AppwriteService? appwriteService,
    AppwriteErrorHandler? errorHandler,
  }) : _appwriteService = appwriteService ?? AppwriteService(),
       _errorHandler = errorHandler ?? AppwriteErrorHandler();
  final AppwriteService _appwriteService;
  final AppwriteErrorHandler _errorHandler;

  String get _collectionId => AppwriteConfig.roomsCollectionId;

  @override
  Future<Room?> getById(String id) async {
    try {
      final doc = await _appwriteService.getDocument(
        collectionId: _collectionId,
        documentId: id,
      );

      return RoomAppwriteExtension.fromAppwriteDocument(doc);
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'getById($id)');

      // إذا كان الخطأ 404، نرجع null بدلاً من رمي خطأ
      if (error.code == 'NOT_FOUND') {
        return null;
      }

      throw Exception(error.message);
    }
  }

  @override
  Future<List<Room>> getAll() async {
    try {
      final documents = await _appwriteService.listDocuments(
        collectionId: _collectionId,
      );

      return documents.map(RoomAppwriteExtension.fromAppwriteDocument).toList();
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'getAll');
      throw Exception(error.message);
    }
  }

  @override
  Future<Room> create(Room room) async {
    try {
      final doc = await _appwriteService.createDocument(
        collectionId: _collectionId,
        documentId: room.localUuid,
        data: room.toJson(),
      );

      return RoomAppwriteExtension.fromAppwriteDocument(doc);
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'create');
      throw Exception(error.message);
    }
  }

  @override
  Future<Room> update(String id, Room room) async {
    try {
      final doc = await _appwriteService.updateDocument(
        collectionId: _collectionId,
        documentId: id,
        data: room.toJson(),
      );

      return RoomAppwriteExtension.fromAppwriteDocument(doc);
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'update($id)');
      throw Exception(error.message);
    }
  }

  @override
  Future<void> delete(String id) async {
    try {
      await _appwriteService.deleteDocument(
        collectionId: _collectionId,
        documentId: id,
      );
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'delete($id)');

      // إذا كان الخطأ 404، نعتبرها نجاح
      if (error.code == 'NOT_FOUND') {
        return;
      }

      throw Exception(error.message);
    }
  }

  @override
  Future<List<Room>> search(String query) async {
    try {
      final queries = AdvancedQueryBuilder()
          .search('room_number', query)
          .orderAsc('room_number')
          .build();

      final documents = await _appwriteService.listDocuments(
        collectionId: _collectionId,
        queries: queries,
      );

      return documents.map(RoomAppwriteExtension.fromAppwriteDocument).toList();
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'search($query)');
      throw Exception(error.message);
    }
  }

  @override
  Future<List<Room>> getAvailable() async {
    try {
      final queries = AdvancedQueryBuilder()
          .where('status', 'شاغرة')
          .orderAsc('room_number')
          .build();

      final documents = await _appwriteService.listDocuments(
        collectionId: _collectionId,
        queries: queries,
      );

      return documents.map(RoomAppwriteExtension.fromAppwriteDocument).toList();
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'getAvailable');
      throw Exception(error.message);
    }
  }

  @override
  Future<List<Room>> getByPriceRange(double min, double max) async {
    try {
      final queries = AdvancedQueryBuilder()
          .whereBetween('price', min, max)
          .orderAsc('price')
          .build();

      final documents = await _appwriteService.listDocuments(
        collectionId: _collectionId,
        queries: queries,
      );

      return documents.map(RoomAppwriteExtension.fromAppwriteDocument).toList();
    } catch (e) {
      final error = _errorHandler.handleError(
        e,
        context: 'getByPriceRange($min, $max)',
      );
      throw Exception(error.message);
    }
  }

  @override
  Future<List<Room>> getPaginated({int limit = 25, int offset = 0}) async {
    try {
      final queries = AdvancedQueryBuilder()
          .limit(limit)
          .offset(offset)
          .orderAsc('room_number')
          .build();

      final documents = await _appwriteService.listDocuments(
        collectionId: _collectionId,
        queries: queries,
      );

      return documents.map(RoomAppwriteExtension.fromAppwriteDocument).toList();
    } catch (e) {
      final error = _errorHandler.handleError(
        e,
        context: 'getPaginated(limit: $limit, offset: $offset)',
      );
      throw Exception(error.message);
    }
  }

  /// الحصول على إحصائيات الغرف
  Future<RoomStatistics> getStatistics() async {
    try {
      final allRooms = await getAll();

      final available = allRooms.where((r) => r.status == 'شاغرة').length;
      final occupied = allRooms.where((r) => r.status == 'محجوزة').length;

      final prices = allRooms.map((r) => r.price).toList();
      prices.sort();

      return RoomStatistics(
        total: allRooms.length,
        available: available,
        occupied: occupied,
        minPrice: prices.isNotEmpty ? prices.first : 0,
        maxPrice: prices.isNotEmpty ? prices.last : 0,
        avgPrice: prices.isNotEmpty
            ? prices.reduce((a, b) => a + b) / prices.length
            : 0,
      );
    } catch (e) {
      final error = _errorHandler.handleError(e, context: 'getStatistics');
      throw Exception(error.message);
    }
  }
}

/// إحصائيات الغرف
class RoomStatistics {
  RoomStatistics({
    required this.total,
    required this.available,
    required this.occupied,
    required this.minPrice,
    required this.maxPrice,
    required this.avgPrice,
  });
  final int total;
  final int available;
  final int occupied;
  final double minPrice;
  final double maxPrice;
  final double avgPrice;

  double get occupancyRate => total > 0 ? occupied / total : 0.0;

  @override
  String toString() =>
      '''
RoomStatistics:
  Total: $total
  Available: $available
  Occupied: $occupied
  Occupancy Rate: ${(occupancyRate * 100).toStringAsFixed(1)}%
  Price Range: $minPrice - $maxPrice
  Average Price: ${avgPrice.toStringAsFixed(2)}
''';
}

/// امتداد للـ Room Model لدعم Appwrite Document
extension RoomAppwriteExtension on Room {
  static Room fromAppwriteDocument(models.Document doc) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return Room(
      id: int.tryParse(doc.$id) ?? 0,
      localUuid: doc.data['localUuid'] as String? ?? doc.$id,
      serverId: doc.data['serverId'] as int?,
      roomNumber: doc.data['room_number'] as String,
      type: doc.data['type'] as String,
      price: (doc.data['price'] as num).toDouble(),
      status: doc.data['status'] as String,
      imageUrl: doc.data['image_url'] as String?,
      cleaningStatus: doc.data['cleaning_status'] as String? ?? 'clean',
      lastCleanedHotelDay: doc.data['last_cleaned'] as String?,
      lastOccupiedHotelDay: doc.data['last_occupied'] as String?,
      requiresMaintenance: doc.data['requires_maintenance'] as bool? ?? false,
      createdAt: now,
      updatedAt: now,
      lastModified: now,
      createdAtEpoch: now,
      lastModifiedEpoch: now,
      version: 1,
      origin: 'cloud',
      vectorClock: {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'room_number': roomNumber,
      'type': type,
      'price': price,
      'status': status,
      if (imageUrl != null) 'image_url': imageUrl,
      if (cleaningStatus.isNotEmpty) 'cleaning_status': cleaningStatus,
      if (lastCleanedHotelDay != null) 'last_cleaned': lastCleanedHotelDay,
      if (lastOccupiedHotelDay != null) 'last_occupied': lastOccupiedHotelDay,
      'requires_maintenance': requiresMaintenance,
      'localUuid': localUuid,
      if (serverId != null) 'serverId': serverId,
    };
  }
}
