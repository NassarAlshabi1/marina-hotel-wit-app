# أمثلة عملية متقدمة: Appwrite + Flutter

## 🚀 أمثلة من مشاريع حقيقية

### 1. Retry Logic مع Exponential Backoff

```dart
class RetryHelper {
  static Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
  }) async {
    int attempts = 0;
    Duration delay = initialDelay;
    
    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempts++;
        
        if (attempts >= maxAttempts) {
          rethrow;
        }
        
        // التحقق من نوع الخطأ
        if (e is AppwriteException) {
          // لا تعيد المحاولة على أخطاء دائمة
          if ([400, 401, 403, 404, 409].contains(e.code)) {
            rethrow;
          }
        }
        
        // انتظر قبل المحاولة التالية
        await Future.delayed(delay);
        
        // مضاعفة وقت الانتظار (Exponential Backoff)
        delay *= 2;
      }
    }
  }
}

// الاستخدام
final rooms = await RetryHelper.withRetry(
  operation: () => appwriteService.databases.listDocuments(
    databaseId: 'hotel_db',
    collectionId: 'rooms',
  ),
  maxAttempts: 3,
);
```

---

### 2. Connection State Manager

```dart
class ConnectionStateManager extends ChangeNotifier {
  ConnectionStatus _status = ConnectionStatus.unknown;
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  
  ConnectionStatus get status => _status;
  bool get isOnline => _status == ConnectionStatus.online;
  
  void init() {
    // الاستماع لتغيرات الاتصال
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _checkConnection();
    });
    
    // فحص أولي
    _checkConnection();
  }
  
  Future<void> _checkConnection() async {
    try {
      // محاولة طلب بسيط للتحقق من الاتصال
      await AppwriteService().databases.listDocuments(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        queries: [Query.limit(1)],
      ).timeout(Duration(seconds: 5));
      
      _updateStatus(ConnectionStatus.online);
    } catch (e) {
      _updateStatus(ConnectionStatus.offline);
    }
  }
  
  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      _status = newStatus;
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

enum ConnectionStatus { online, offline, unknown }

// في الـ UI
class RoomsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectionStateManager>(
      builder: (context, connection, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text('الغرف'),
            backgroundColor: connection.isOnline 
                ? Colors.green 
                : Colors.red,
          ),
          body: connection.isOnline
              ? OnlineRoomsList()
              : OfflineRoomsList(),
        );
      },
    );
  }
}
```

---

### 3. Optimistic Updates

```dart
class OptimisticUpdateService {
  final List<Room> _localRooms = [];
  final StreamController<List<Room>> _controller = StreamController.broadcast();
  
  Stream<List<Room>> get roomsStream => _controller.stream;
  
  /// تحديث متفائل - تحديث UI فوراً، ثم السيرفر
  Future<void> updateRoomOptimistically(Room updatedRoom) async {
    // 1. حفظ النسخة الأصلية
    final originalRoom = _localRooms.firstWhere(
      (r) => r.id == updatedRoom.id,
    );
    
    // 2. تحديث محلي فوري
    final index = _localRooms.indexWhere((r) => r.id == updatedRoom.id);
    _localRooms[index] = updatedRoom;
    _controller.add(List.from(_localRooms));
    
    try {
      // 3. تحديث السيرفر في الخلفية
      await AppwriteService().databases.updateDocument(
        databaseId: 'hotel_db',
        collectionId: 'rooms',
        documentId: updatedRoom.id,
        data: updatedRoom.toJson(),
      );
    } catch (e) {
      // 4. عند الفشل، استرجاع النسخة الأصلية
      _localRooms[index] = originalRoom;
      _controller.add(List.from(_localRooms));
      
      // عرض رسالة خطأ
      throw Exception('فشل التحديث: ${AppwriteErrorHandler.handleError(e)}');
    }
  }
}
```

---

### 4. Batch Operations

```dart
class BatchOperationsService {
  /// حذف عدة عناصر دفعة واحدة
  Future<BatchResult> deleteMultiple(List<String> ids) async {
    final results = <String, bool>{};
    final errors = <String, String>{};
    
    // استخدام Future.wait للتوازي
    await Future.wait(
      ids.map((id) async {
        try {
          await AppwriteService().databases.deleteDocument(
            databaseId: 'hotel_db',
            collectionId: 'rooms',
            documentId: id,
          );
          results[id] = true;
        } catch (e) {
          results[id] = false;
          errors[id] = AppwriteErrorHandler.handleError(e);
        }
      }),
    );
    
    return BatchResult(
      total: ids.length,
      successful: results.values.where((v) => v).length,
      failed: results.values.where((v) => !v).length,
      errors: errors,
    );
  }
  
  /// إنشاء عدة عناصر دفعة واحدة
  Future<List<Room>> createMultiple(List<Room> rooms) async {
    final createdRooms = <Room>[];
    
    for (final room in rooms) {
      try {
        final doc = await AppwriteService().databases.createDocument(
          databaseId: 'hotel_db',
          collectionId: 'rooms',
          documentId: ID.unique(),
          data: room.toJson(),
        );
        createdRooms.add(Room.fromDocument(doc));
      } catch (e) {
        print('Failed to create room: ${room.roomNumber}');
      }
    }
    
    return createdRooms;
  }
}

class BatchResult {
  final int total;
  final int successful;
  final int failed;
  final Map<String, String> errors;
  
  BatchResult({
    required this.total,
    required this.successful,
    required this.failed,
    required this.errors,
  });
  
  bool get isFullSuccess => failed == 0;
  bool get isPartialSuccess => successful > 0 && failed > 0;
  bool get isFullFailure => successful == 0;
}
```

---

### 5. Advanced Query Builder

```dart
class AdvancedQueryBuilder {
  final List<String> _queries = [];
  
  AdvancedQueryBuilder where(String attribute, dynamic value) {
    _queries.add(Query.equal(attribute, value));
    return this;
  }
  
  AdvancedQueryBuilder whereIn(String attribute, List<dynamic> values) {
    for (final value in values) {
      _queries.add(Query.equal(attribute, value));
    }
    return this;
  }
  
  AdvancedQueryBuilder whereBetween(
    String attribute,
    dynamic min,
    dynamic max,
  ) {
    _queries.add(Query.greaterThanEqual(attribute, min));
    _queries.add(Query.lessThanEqual(attribute, max));
    return this;
  }
  
  AdvancedQueryBuilder search(String attribute, String term) {
    _queries.add(Query.search(attribute, term));
    return this;
  }
  
  AdvancedQueryBuilder orderBy(String attribute, {bool desc = false}) {
    _queries.add(
      desc ? Query.orderDesc(attribute) : Query.orderAsc(attribute),
    );
    return this;
  }
  
  AdvancedQueryBuilder limit(int value) {
    _queries.add(Query.limit(value));
    return this;
  }
  
  AdvancedQueryBuilder offset(int value) {
    _queries.add(Query.offset(value));
    return this;
  }
  
  List<String> build() => _queries;
}

// الاستخدام
final queries = AdvancedQueryBuilder()
    .where('status', 'شاغرة')
    .whereBetween('price', 10000, 20000)
    .orderBy('price', desc: false)
    .limit(50)
    .build();

final rooms = await appwriteService.databases.listDocuments(
  databaseId: 'hotel_db',
  collectionId: 'rooms',
  queries: queries,
);
```

---

### 6. Realtime Updates مع State Management

```dart
class RealtimeRoomsProvider extends ChangeNotifier {
  final List<Room> _rooms = [];
  RealtimeSubscription? _subscription;
  bool _isSubscribed = false;
  
  List<Room> get rooms => List.unmodifiable(_rooms);
  bool get isSubscribed => _isSubscribed;
  
  Future<void> subscribe() async {
    if (_isSubscribed) return;
    
    try {
      // جلب البيانات الأولية
      await _fetchInitialData();
      
      // الاشتراك في التحديثات
      final realtime = Realtime(AppwriteService()._client);
      _subscription = realtime.subscribe([
        'databases.hotel_db.collections.rooms.documents',
      ]);
      
      _subscription!.stream.listen((response) {
        _handleRealtimeEvent(response);
      });
      
      _isSubscribed = true;
      notifyListeners();
    } catch (e) {
      throw Exception('فشل الاشتراك: ${AppwriteErrorHandler.handleError(e)}');
    }
  }
  
  void _handleRealtimeEvent(RealtimeMessage message) {
    final events = message.events;
    
    if (events.contains('databases.*.collections.*.documents.*.create')) {
      final room = Room.fromJson(message.payload);
      _rooms.add(room);
      notifyListeners();
    } else if (events.contains('databases.*.collections.*.documents.*.update')) {
      final room = Room.fromJson(message.payload);
      final index = _rooms.indexWhere((r) => r.id == room.id);
      if (index != -1) {
        _rooms[index] = room;
        notifyListeners();
      }
    } else if (events.contains('databases.*.collections.*.documents.*.delete')) {
      final roomId = message.payload['\$id'];
      _rooms.removeWhere((r) => r.id == roomId);
      notifyListeners();
    }
  }
  
  Future<void> _fetchInitialData() async {
    final response = await AppwriteService().databases.listDocuments(
      databaseId: 'hotel_db',
      collectionId: 'rooms',
    );
    
    _rooms.clear();
    _rooms.addAll(
      response.documents.map((doc) => Room.fromDocument(doc)),
    );
    notifyListeners();
  }
  
  void unsubscribe() {
    _subscription?.close();
    _subscription = null;
    _isSubscribed = false;
    notifyListeners();
  }
  
  @override
  void dispose() {
    unsubscribe();
    super.dispose();
  }
}

// في الـ UI
class RealtimeRoomsList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RealtimeRoomsProvider>(
      builder: (context, provider, child) {
        if (!provider.isSubscribed) {
          provider.subscribe();
          return Center(child: CircularProgressIndicator());
        }
        
        return ListView.builder(
          itemCount: provider.rooms.length,
          itemBuilder: (context, index) {
            return RoomListTile(room: provider.rooms[index]);
          },
        );
      },
    );
  }
}
```

---

### 7. File Upload مع Progress

```dart
class FileUploadService {
  final Storage _storage = AppwriteService().storage;
  
  Future<String> uploadFileWithProgress({
    required File file,
    required String bucketId,
    required ValueChanged<double> onProgress,
  }) async {
    try {
      final fileId = ID.unique();
      final fileSize = await file.length();
      int uploadedBytes = 0;
      
      // رفع الملف مع تتبع التقدم
      final uploadedFile = await _storage.createFile(
        bucketId: bucketId,
        fileId: fileId,
        file: InputFile.fromPath(
          path: file.path,
          filename: path.basename(file.path),
        ),
        onProgress: (UploadProgress progress) {
          uploadedBytes = progress.chunksUploaded * progress.chunkSize;
          final percentage = (uploadedBytes / fileSize).clamp(0.0, 1.0);
          onProgress(percentage);
        },
      );
      
      return uploadedFile.$id;
    } catch (e) {
      throw Exception('فشل رفع الملف: ${AppwriteErrorHandler.handleError(e)}');
    }
  }
  
  /// حذف ملف قديم ورفع جديد
  Future<String> replaceFile({
    required File newFile,
    required String bucketId,
    String? oldFileId,
    required ValueChanged<double> onProgress,
  }) async {
    // حذف الملف القديم إن وجد
    if (oldFileId != null) {
      try {
        await _storage.deleteFile(
          bucketId: bucketId,
          fileId: oldFileId,
        );
      } on AppwriteException catch (e) {
        if (e.code != 404) rethrow;
        // 404 = الملف محذوف بالفعل، نكمل
      }
    }
    
    // رفع الملف الجديد
    return await uploadFileWithProgress(
      file: newFile,
      bucketId: bucketId,
      onProgress: onProgress,
    );
  }
}

// في الـ UI
class ImageUploadWidget extends StatefulWidget {
  @override
  _ImageUploadWidgetState createState() => _ImageUploadWidgetState();
}

class _ImageUploadWidgetState extends State<ImageUploadWidget> {
  double _uploadProgress = 0.0;
  bool _isUploading = false;
  
  Future<void> _uploadImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    
    if (pickedFile == null) return;
    
    setState(() => _isUploading = true);
    
    try {
      final fileId = await FileUploadService().uploadFileWithProgress(
        file: File(pickedFile.path),
        bucketId: 'room-images',
        onProgress: (progress) {
          setState(() => _uploadProgress = progress);
        },
      );
      
      print('File uploaded: $fileId');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      setState(() {
        _isUploading = false;
        _uploadProgress = 0.0;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _isUploading ? null : _uploadImage,
          child: Text('رفع صورة'),
        ),
        if (_isUploading)
          Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(value: _uploadProgress),
                SizedBox(height: 8),
                Text('${(_uploadProgress * 100).toInt()}%'),
              ],
            ),
          ),
      ],
    );
  }
}
```

---

### 8. Advanced Error Logging

```dart
class ErrorLogger {
  static final List<ErrorLog> _logs = [];
  static const int _maxLogs = 100;
  
  static void log({
    required String error,
    required String context,
    StackTrace? stackTrace,
    Map<String, dynamic>? metadata,
  }) {
    final errorLog = ErrorLog(
      error: error,
      context: context,
      stackTrace: stackTrace,
      metadata: metadata,
      timestamp: DateTime.now(),
    );
    
    _logs.insert(0, errorLog);
    
    // الحفاظ على آخر 100 خطأ فقط
    if (_logs.length > _maxLogs) {
      _logs.removeRange(_maxLogs, _logs.length);
    }
    
    // إرسال للسيرفر في حالة الأخطاء الحرجة
    if (_isCritical(error)) {
      _sendToServer(errorLog);
    }
  }
  
  static bool _isCritical(String error) {
    return error.contains('500') || 
           error.contains('503') || 
           error.contains('crash');
  }
  
  static Future<void> _sendToServer(ErrorLog log) async {
    try {
      await AppwriteService().databases.createDocument(
        databaseId: 'hotel_db',
        collectionId: 'error_logs',
        documentId: ID.unique(),
        data: log.toJson(),
      );
    } catch (e) {
      print('Failed to log error: $e');
    }
  }
  
  static List<ErrorLog> getLogs() => List.unmodifiable(_logs);
  
  static void clearLogs() => _logs.clear();
}

class ErrorLog {
  final String error;
  final String context;
  final StackTrace? stackTrace;
  final Map<String, dynamic>? metadata;
  final DateTime timestamp;
  
  ErrorLog({
    required this.error,
    required this.context,
    this.stackTrace,
    this.metadata,
    required this.timestamp,
  });
  
  Map<String, dynamic> toJson() => {
    'error': error,
    'context': context,
    'stack_trace': stackTrace?.toString(),
    'metadata': metadata,
    'timestamp': timestamp.toIso8601String(),
  };
}
```

---

## 🎯 نصائح الأداء

### 1. تجنب الطلبات المتكررة

```dart
// ❌ خطأ
for (var roomId in roomIds) {
  final room = await getRoom(roomId); // N+1 problem
}

// ✅ صحيح
final rooms = await getRoomsByIds(roomIds); // استعلام واحد
```

### 2. استخدام Debouncing للبحث

```dart
class SearchDebouncer {
  Timer? _timer;
  
  void run(VoidCallback action, {Duration delay = const Duration(milliseconds: 500)}) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }
  
  void dispose() {
    _timer?.cancel();
  }
}

// الاستخدام
final _debouncer = SearchDebouncer();

void onSearchChanged(String query) {
  _debouncer.run(() {
    // تنفيذ البحث بعد 500ms من توقف الكتابة
    performSearch(query);
  });
}
```

### 3. Lazy Loading للصور

```dart
CachedNetworkImage(
  imageUrl: room.imageUrl,
  placeholder: (context, url) => CircularProgressIndicator(),
  errorWidget: (context, url, error) => Icon(Icons.error),
  memCacheWidth: 400, // تحسين الذاكرة
  memCacheHeight: 300,
)
```

---

## 📊 مثال كامل: نظام الغرف

راجع الملف `@sync/services/appwrite_service.dart` في المشروع للاطلاع على:
- ✅ معالجة 404 في الحذف
- ✅ Singleton Pattern
- ✅ Error Handling شامل
- ✅ Retry Logic
- ✅ Timeout Management

---

**تاريخ التحديث**: 2026-01-28  
**الإصدار**: 1.0
