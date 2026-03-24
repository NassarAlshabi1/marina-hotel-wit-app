# أفضل ممارسات Appwrite مع Flutter/Dart لتطبيقات بدون أخطاء

## 📚 المصادر المعتمدة

هذا الدليل مجمّع من:
- Appwrite Official Documentation
- Appwrite SDK for Flutter (GitHub)
- Appwrite Discussions & Issues
- أفضل المستودعات المفتوحة المصدر
- تجارب مشاريع Production

---

## 1️⃣ معالجة الأخطاء (Error Handling)

### ✅ الطريقة الصحيحة: معالجة شاملة للأخطاء

```dart
import 'package:appwrite/appwrite.dart';

class AppwriteErrorHandler {
  /// معالجة شاملة لأخطاء Appwrite
  static String handleError(dynamic error) {
    if (error is AppwriteException) {
      // معالجة أخطاء Appwrite حسب الكود
      switch (error.code) {
        case 401: // Unauthorized
          return 'يرجى تسجيل الدخول مرة أخرى';
        
        case 404: // Not Found
          return 'العنصر المطلوب غير موجود';
        
        case 409: // Conflict
          return 'يوجد تعارض في البيانات';
        
        case 500: // Server Error
          return 'خطأ في السيرفر، يرجى المحاولة لاحقاً';
        
        case 503: // Service Unavailable
          return 'الخدمة غير متاحة حالياً';
        
        default:
          return error.message ?? 'حدث خطأ غير متوقع';
      }
    }
    
    return 'حدث خطأ: ${error.toString()}';
  }
  
  /// معالجة ذكية للحذف (يتجاهل 404)
  static Future<void> deleteSilently(
    Future<void> Function() deleteOperation
  ) async {
    try {
      await deleteOperation();
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // العنصر محذوف بالفعل - نجاح!
        return;
      }
      rethrow; // أخطاء أخرى تُرمى للمعالجة
    }
  }
}
```

### ✅ نمط Try-Catch الموصى به

```dart
class RoomService {
  final Databases databases;
  
  Future<Document?> getRoom(String roomId) async {
    try {
      final document = await databases.getDocument(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        documentId: roomId,
      );
      return document;
    } on AppwriteException catch (e) {
      if (e.code == 404) {
        // العنصر غير موجود
        return null;
      }
      
      if (e.code == 401) {
        // غير مصرح - إعادة تسجيل الدخول
        throw UnauthorizedException('يرجى تسجيل الدخول');
      }
      
      // أخطاء أخرى
      throw Exception(AppwriteErrorHandler.handleError(e));
    } catch (e) {
      // أخطاء عامة (شبكة، إلخ)
      throw Exception('فشل الاتصال بالسيرفر');
    }
  }
  
  Future<void> deleteRoom(String roomId) async {
    await AppwriteErrorHandler.deleteSilently(
      () => databases.deleteDocument(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        documentId: roomId,
      ),
    );
  }
}
```

---

## 2️⃣ إعداد Client بشكل صحيح

### ✅ Singleton Pattern للـ Client

```dart
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  
  late final Client _client;
  late final Account _account;
  late final Databases _databases;
  late final Storage _storage;
  
  bool _initialized = false;
  
  Future<void> init({
    required String endpoint,
    required String projectId,
    String? selfSigned, // للتطوير فقط
  }) async {
    if (_initialized) return;
    
    _client = Client()
      ..setEndpoint(endpoint)
      ..setProject(projectId);
    
    // للتطوير المحلي فقط
    if (selfSigned == 'true') {
      _client.setSelfSigned(status: true);
    }
    
    _account = Account(_client);
    _databases = Databases(_client);
    _storage = Storage(_client);
    
    _initialized = true;
  }
  
  void ensureInitialized() {
    if (!_initialized) {
      throw Exception('AppwriteService not initialized');
    }
  }
  
  // Getters
  Account get account {
    ensureInitialized();
    return _account;
  }
  
  Databases get databases {
    ensureInitialized();
    return _databases;
  }
  
  Storage get storage {
    ensureInitialized();
    return _storage;
  }
}
```

### ✅ تهيئة في main()

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة Appwrite
  await AppwriteService().init(
    endpoint: 'https://cloud.appwrite.io/v1',
    projectId: 'YOUR_PROJECT_ID',
  );
  
  runApp(MyApp());
}
```

---

## 3️⃣ المصادقة والجلسات (Authentication & Sessions)

### ✅ التحقق من الجلسة بشكل دوري

```dart
class AuthService {
  final Account _account = AppwriteService().account;
  
  /// التحقق من وجود جلسة نشطة
  Future<bool> hasActiveSession() async {
    try {
      await _account.get();
      return true;
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        return false; // لا توجد جلسة
      }
      rethrow;
    }
  }
  
  /// تسجيل الدخول
  Future<models.Session> login({
    required String email,
    required String password,
  }) async {
    try {
      return await _account.createEmailPasswordSession(
        email: email,
        password: password,
      );
    } on AppwriteException catch (e) {
      if (e.code == 401) {
        throw Exception('بيانات الدخول غير صحيحة');
      }
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  /// تسجيل الخروج
  Future<void> logout() async {
    try {
      await _account.deleteSession(sessionId: 'current');
    } on AppwriteException catch (e) {
      if (e.code == 401 || e.code == 404) {
        // الجلسة منتهية بالفعل
        return;
      }
      rethrow;
    }
  }
}
```

### ✅ Global Error Interceptor

```dart
class AppwriteInterceptor {
  static void setupGlobalErrorHandler() {
    FlutterError.onError = (FlutterErrorDetails details) {
      final error = details.exception;
      
      if (error is AppwriteException && error.code == 401) {
        // تسجيل الخروج التلقائي
        AuthService().logout();
        // التوجيه لصفحة تسجيل الدخول
        navigatorKey.currentState?.pushReplacementNamed('/login');
      }
      
      // معالجة أخطاء أخرى
      FlutterError.presentError(details);
    };
  }
}
```

---

## 4️⃣ العمليات على البيانات (CRUD Operations)

### ✅ Repository Pattern

```dart
abstract class BaseRepository<T> {
  Future<T?> getById(String id);
  Future<List<T>> getAll();
  Future<T> create(T item);
  Future<T> update(String id, T item);
  Future<void> delete(String id);
}

class RoomRepository implements BaseRepository<Room> {
  final Databases _databases = AppwriteService().databases;
  final String _databaseId = 'hotel_db';
  final String _collectionId = 'rooms';
  
  @override
  Future<Room?> getById(String id) async {
    try {
      final doc = await _databases.getDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: id,
      );
      return Room.fromDocument(doc);
    } on AppwriteException catch (e) {
      if (e.code == 404) return null;
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  @override
  Future<List<Room>> getAll() async {
    try {
      final response = await _databases.listDocuments(
        databaseId: _databaseId,
        collectionId: _collectionId,
      );
      return response.documents
          .map((doc) => Room.fromDocument(doc))
          .toList();
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  @override
  Future<Room> create(Room room) async {
    try {
      final doc = await _databases.createDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: ID.unique(),
        data: room.toJson(),
      );
      return Room.fromDocument(doc);
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  @override
  Future<Room> update(String id, Room room) async {
    try {
      final doc = await _databases.updateDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: id,
        data: room.toJson(),
      );
      return Room.fromDocument(doc);
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  @override
  Future<void> delete(String id) async {
    await AppwriteErrorHandler.deleteSilently(
      () => _databases.deleteDocument(
        databaseId: _databaseId,
        collectionId: _collectionId,
        documentId: id,
      ),
    );
  }
}
```

---

## 5️⃣ الاستعلامات والفلترة (Queries & Filtering)

### ✅ استخدام Query Builders

```dart
class RoomQueries {
  final Databases _databases = AppwriteService().databases;
  
  /// البحث عن الغرف الشاغرة
  Future<List<Room>> getAvailableRooms() async {
    try {
      final response = await _databases.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [
          Query.equal('status', 'شاغرة'),
          Query.orderDesc('\$createdAt'),
        ],
      );
      return response.documents
          .map((doc) => Room.fromDocument(doc))
          .toList();
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  /// البحث بالسعر
  Future<List<Room>> getRoomsByPriceRange({
    required double minPrice,
    required double maxPrice,
  }) async {
    try {
      final response = await _databases.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [
          Query.greaterThanEqual('price', minPrice),
          Query.lessThanEqual('price', maxPrice),
          Query.orderAsc('price'),
        ],
      );
      return response.documents
          .map((doc) => Room.fromDocument(doc))
          .toList();
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  /// البحث النصي
  Future<List<Room>> searchRooms(String searchTerm) async {
    try {
      final response = await _databases.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [
          Query.search('room_number', searchTerm),
        ],
      );
      return response.documents
          .map((doc) => Room.fromDocument(doc))
          .toList();
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
  
  /// Pagination
  Future<List<Room>> getRoomsPaginated({
    int limit = 25,
    int offset = 0,
  }) async {
    try {
      final response = await _databases.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [
          Query.limit(limit),
          Query.offset(offset),
        ],
      );
      return response.documents
          .map((doc) => Room.fromDocument(doc))
          .toList();
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
}
```

---

## 6️⃣ Realtime Subscriptions

### ✅ الاشتراك في التحديثات الفورية

```dart
class RealtimeService {
  final Realtime _realtime = Realtime(AppwriteService()._client);
  RealtimeSubscription? _subscription;
  
  /// الاشتراك في تحديثات الغرف
  void subscribeToRooms({
    required Function(RealtimeMessage) onUpdate,
    required Function(dynamic) onError,
  }) {
    try {
      _subscription = _realtime.subscribe([
        'databases.hotel_db.collections.rooms.documents',
      ]);
      
      _subscription!.stream.listen(
        (response) {
          onUpdate(response);
        },
        onError: (error) {
          if (error is AppwriteException) {
            onError(AppwriteErrorHandler.handleError(error));
          } else {
            onError(error.toString());
          }
        },
      );
    } catch (e) {
      onError(AppwriteErrorHandler.handleError(e));
    }
  }
  
  /// إلغاء الاشتراك
  void unsubscribe() {
    _subscription?.close();
    _subscription = null;
  }
}
```

---

## 7️⃣ Offline Support & Sync

### ✅ استراتيجية Offline-First

```dart
class OfflineSyncService {
  final LocalDatabase localDb;
  final Databases remoteDb = AppwriteService().databases;
  
  /// جلب البيانات مع دعم Offline
  Future<List<Room>> getRoomsOfflineFirst() async {
    // 1. جلب من Local أولاً
    final localRooms = await localDb.getAllRooms();
    
    // 2. محاولة المزامنة في الخلفية
    syncInBackground();
    
    // 3. إرجاع البيانات المحلية فوراً
    return localRooms;
  }
  
  /// المزامنة في الخلفية
  Future<void> syncInBackground() async {
    try {
      // التحقق من الاتصال
      final hasConnection = await checkConnectivity();
      if (!hasConnection) return;
      
      // جلب من Remote
      final response = await remoteDb.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
      );
      
      // تحديث Local Database
      await localDb.updateRooms(
        response.documents.map((d) => Room.fromDocument(d)).toList(),
      );
    } catch (e) {
      // فشل المزامنة - البيانات المحلية لا تزال صالحة
      print('Sync failed: ${AppwriteErrorHandler.handleError(e)}');
    }
  }
  
  /// التحقق من الاتصال
  Future<bool> checkConnectivity() async {
    try {
      await remoteDb.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [Query.limit(1)],
      );
      return true;
    } catch (e) {
      return false;
    }
  }
}
```

---

## 8️⃣ Performance Best Practices

### ✅ Pagination & Lazy Loading

```dart
class PaginatedRoomList extends StatefulWidget {
  @override
  _PaginatedRoomListState createState() => _PaginatedRoomListState();
}

class _PaginatedRoomListState extends State<PaginatedRoomList> {
  final List<Room> _rooms = [];
  final int _pageSize = 25;
  int _currentOffset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  
  @override
  void initState() {
    super.initState();
    _loadMore();
  }
  
  Future<void> _loadMore() async {
    if (_isLoading || !_hasMore) return;
    
    setState(() => _isLoading = true);
    
    try {
      final newRooms = await RoomQueries().getRoomsPaginated(
        limit: _pageSize,
        offset: _currentOffset,
      );
      
      setState(() {
        _rooms.addAll(newRooms);
        _currentOffset += newRooms.length;
        _hasMore = newRooms.length == _pageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppwriteErrorHandler.handleError(e))),
      );
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _rooms.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _rooms.length) {
          // نهاية القائمة - تحميل المزيد
          _loadMore();
          return Center(child: CircularProgressIndicator());
        }
        return RoomListTile(room: _rooms[index]);
      },
    );
  }
}
```

### ✅ Caching Strategy

```dart
class CachedDataService {
  final Map<String, CachedData> _cache = {};
  final Duration _cacheDuration = Duration(minutes: 5);
  
  Future<T> getCached<T>({
    required String key,
    required Future<T> Function() fetcher,
  }) async {
    // التحقق من Cache
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      if (!cached.isExpired) {
        return cached.data as T;
      }
    }
    
    // جلب بيانات جديدة
    final data = await fetcher();
    
    // حفظ في Cache
    _cache[key] = CachedData(
      data: data,
      expiresAt: DateTime.now().add(_cacheDuration),
    );
    
    return data;
  }
  
  void clearCache([String? key]) {
    if (key != null) {
      _cache.remove(key);
    } else {
      _cache.clear();
    }
  }
}

class CachedData {
  final dynamic data;
  final DateTime expiresAt;
  
  CachedData({required this.data, required this.expiresAt});
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
```

---

## 9️⃣ Security Best Practices

### ✅ لا تكشف الأسرار في الكود

```dart
// ❌ خطأ
const String apiKey = 'my-secret-api-key';

// ✅ صحيح - استخدم Environment Variables
class AppConfig {
  static String get endpoint => 
      const String.fromEnvironment('APPWRITE_ENDPOINT');
  
  static String get projectId => 
      const String.fromEnvironment('APPWRITE_PROJECT_ID');
}

// أو استخدم flutter_dotenv
import 'package:flutter_dotenv/flutter_dotenv.dart';

await dotenv.load();
final endpoint = dotenv.env['APPWRITE_ENDPOINT']!;
```

### ✅ Server-Side Validation

```dart
// لا تعتمد فقط على التحقق من الصلاحيات في Client
// استخدم Appwrite Functions للتحقق من الصلاحيات على السيرفر

class SecureOperations {
  /// حذف حجز - مع التحقق من الصلاحيات
  Future<void> deleteBooking(String bookingId) async {
    try {
      // استدعاء Function للتحقق
      await Functions(AppwriteService()._client).createExecution(
        functionId: 'delete-booking-with-validation',
        body: json.encode({'bookingId': bookingId}),
      );
    } catch (e) {
      throw Exception(AppwriteErrorHandler.handleError(e));
    }
  }
}
```

---

## 🔟 Testing Best Practices

### ✅ Mock Appwrite للاختبارات

```dart
class MockAppwriteService implements AppwriteService {
  @override
  Future<Document> getDocument({
    required String databaseId,
    required String collectionId,
    required String documentId,
  }) async {
    // إرجاع بيانات تجريبية
    return Document(
      $id: documentId,
      $collectionId: collectionId,
      $databaseId: databaseId,
      $createdAt: DateTime.now().toIso8601String(),
      $updatedAt: DateTime.now().toIso8601String(),
      $permissions: [],
      data: {
        'room_number': '101',
        'type': 'سرير عائلي',
        'price': 15000,
        'status': 'شاغرة',
      },
    );
  }
}

// في الاختبارات
void main() {
  group('RoomRepository Tests', () {
    late MockAppwriteService mockService;
    late RoomRepository repository;
    
    setUp(() {
      mockService = MockAppwriteService();
      repository = RoomRepository(appwriteService: mockService);
    });
    
    test('should get room by id', () async {
      final room = await repository.getById('test-id');
      expect(room, isNotNull);
      expect(room!.roomNumber, '101');
    });
  });
}
```

---

## 📋 Checklist للمشاريع Production

- [ ] معالجة جميع أكواد الأخطاء الشائعة (401, 404, 409, 500, 503)
- [ ] استخدام Singleton Pattern للـ Client
- [ ] تطبيق Repository Pattern
- [ ] معالجة خطأ 404 في عمليات الحذف كنجاح
- [ ] Global Error Handler للجلسات المنتهية
- [ ] Offline-First Strategy للبيانات الحرجة
- [ ] Pagination للقوائم الطويلة
- [ ] Caching للبيانات المتكررة
- [ ] Environment Variables للأسرار
- [ ] Server-Side Validation للعمليات الحساسة
- [ ] Unit Tests & Integration Tests
- [ ] Error Logging & Monitoring
- [ ] Timeout Handling للطلبات البطيئة
- [ ] Retry Logic للفشل المؤقت
- [ ] Connection State Management

---

## 🎯 الخلاصة

### أهم 5 نقاط:

1. **معالجة الأخطاء بذكاء**: 404 في الحذف = نجاح
2. **Singleton للـ Client**: تجنب إنشاء نسخ متعددة
3. **Offline-First**: البيانات المحلية أولاً، المزامنة في الخلفية
4. **Repository Pattern**: فصل منطق البيانات عن UI
5. **Security**: لا تكشف الأسرار، استخدم Server-Side Validation

---

**تاريخ التحديث**: 2026-01-28  
**الإصدار**: 1.0  
**المصادر**: Appwrite Docs, Flutter Docs, GitHub Repositories
