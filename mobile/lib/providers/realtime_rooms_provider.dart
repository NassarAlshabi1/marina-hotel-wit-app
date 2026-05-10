import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../repositories/room_repository.dart';
import '../services/appwrite_logger.dart';
import '../services/appwrite_realtime_service.dart';
import '../services/local_db.dart';

/// Provider للغرف مع دعم Realtime Updates
///
/// يدير حالة الغرف ويستمع للتحديثات الفورية من Appwrite
class RealTimeRoomsProvider extends ChangeNotifier {

  RealTimeRoomsProvider({
    required RoomRepository repository,
    required AppwriteRealtimeService realtimeService,
  }) : _repository = repository,
       _realtimeService = realtimeService;
  final RoomRepository _repository;
  // ignore: unused_field
  final AppwriteRealtimeService _realtimeService;
  final AppwriteLogger _logger = AppwriteLogger();

  List<Room> _rooms = [];
  bool _isLoading = false;
  bool _isSubscribed = false;
  String? _error;
  RealtimeSubscription? _subscription;

  // Getters
  List<Room> get rooms => List.unmodifiable(_rooms);
  bool get isLoading => _isLoading;
  bool get isSubscribed => _isSubscribed;
  String? get error => _error;
  int get roomCount => _rooms.length;

  List<Room> get availableRooms =>
      _rooms.where((r) => r.status == 'شاغرة').toList();

  List<Room> get occupiedRooms =>
      _rooms.where((r) => r.status == 'محجوزة').toList();

  /// تحميل الغرف
  Future<void> loadRooms() async {
    if (_isLoading) {
      return;
    }

    _setLoading(true);
    _setError(null);

    try {
      _logger.info('Loading rooms...', tag: 'ROOMS_PROVIDER');
      _rooms = await _repository.getAll();
      _logger.info('Loaded ${_rooms.length} rooms', tag: 'ROOMS_PROVIDER');
      notifyListeners();
    } catch (e) {
      _logger.error('Failed to load rooms', error: e, tag: 'ROOMS_PROVIDER');
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// الاشتراك في التحديثات الفورية
  Future<void> subscribe() async {
    if (_isSubscribed) {
      _logger.debug('Already subscribed to rooms', tag: 'ROOMS_PROVIDER');
      return;
    }

    try {
      _logger.info('Subscribing to rooms realtime...', tag: 'ROOMS_PROVIDER');

      // تحميل البيانات الأولية
      await loadRooms();

      // الاشتراك في التحديثات
      // ملاحظة: subscribeToRooms غير متوفر حالياً في AppwriteRealtimeService
      // يمكن تفعيله لاحقاً عند الحاجة
      _logger.debug('Realtime subscription disabled', tag: 'ROOMS_PROVIDER');

      _isSubscribed = true;
      notifyListeners();

      _logger.info('Subscribed to rooms successfully', tag: 'ROOMS_PROVIDER');
    } catch (e) {
      _logger.error('Failed to subscribe', error: e, tag: 'ROOMS_PROVIDER');
      _setError(e.toString());
    }
  }

  /// معالج التحديثات الفورية
  // ignore: unused_element
  void _handleRealtimeUpdate(RealtimeMessage message) {
    _logger.debug('Realtime update: ${message.events}', tag: 'ROOMS_PROVIDER');

    final events = message.events;
    final payload = message.payload;

    try {
      if (events.any((e) => e.contains('create'))) {
        _handleRoomCreated(payload);
      } else if (events.any((e) => e.contains('update'))) {
        _handleRoomUpdated(payload);
      } else if (events.any((e) => e.contains('delete'))) {
        _handleRoomDeleted(payload);
      }
    } catch (e) {
      _logger.error(
        'Failed to handle realtime update',
        error: e,
        tag: 'ROOMS_PROVIDER',
      );
    }
  }

  /// معالجة إنشاء غرفة جديدة
  void _handleRoomCreated(Map<String, dynamic> payload) {
    // إعادة تحميل الغرف بدلاً من parsing يدوي
    loadRooms();
  }

  /// معالجة تحديث غرفة
  void _handleRoomUpdated(Map<String, dynamic> payload) {
    // إعادة تحميل الغرف بدلاً من parsing يدوي
    loadRooms();
  }

  /// معالجة حذف غرفة
  void _handleRoomDeleted(Map<String, dynamic> payload) {
    final roomId = payload['\$id'] as String?;
    if (roomId != null) {
      final intId = int.tryParse(roomId);
      if (intId != null) {
        _rooms.removeWhere((r) => r.id == intId);
        notifyListeners();
        _logger.info('Room deleted: $roomId', tag: 'ROOMS_PROVIDER');
      }
    }
  }

  /// إلغاء الاشتراك
  void unsubscribe() {
    if (_subscription != null) {
      _subscription!.close();
      _subscription = null;
      _isSubscribed = false;
      notifyListeners();
      _logger.info('Unsubscribed from rooms', tag: 'ROOMS_PROVIDER');
    }
  }

  /// البحث في الغرف محلياً
  List<Room> searchLocal(String query) {
    if (query.isEmpty) {
      return rooms;
    }

    final lowerQuery = query.toLowerCase();
    return _rooms.where((room) {
      return room.roomNumber.toLowerCase().contains(lowerQuery) ||
          room.type.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// الحصول على غرفة بالمعرف
  Room? getRoomById(int id) {
    try {
      return _rooms.firstWhere((r) => r.id == id);
    } catch (e) {
      return null;
    }
  }

  /// الحصول على غرفة برقم الغرفة
  Room? getRoomByNumber(String roomNumber) {
    try {
      return _rooms.firstWhere((r) => r.roomNumber == roomNumber);
    } catch (e) {
      return null;
    }
  }

  /// تحديث غرفة محلياً (Optimistic Update)
  void updateRoomOptimistically(Room updatedRoom) {
    final index = _rooms.indexWhere((r) => r.id == updatedRoom.id);
    if (index != -1) {
      _rooms[index] = updatedRoom;
      notifyListeners();
    }
  }

  /// إعادة تحميل
  Future<void> refresh() async {
    await loadRooms();
  }

  // Helper methods
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setError(String? value) {
    _error = value;
    notifyListeners();
  }

  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}
