# ❌ vs ✅ أخطاء شائعة وحلولها في Appwrite + Flutter

## 1. معالجة الأخطاء

### ❌ خطأ: رمي جميع الأخطاء بنفس الطريقة

```dart
Future<Room?> getRoom(String id) async {
  try {
    final doc = await databases.getDocument(...);
    return Room.fromDocument(doc);
  } catch (e) {
    throw Exception('حدث خطأ'); // رسالة غير واضحة
  }
}
```

### ✅ صحيح: معالجة ذكية حسب نوع الخطأ

```dart
Future<Room?> getRoom(String id) async {
  try {
    final doc = await databases.getDocument(...);
    return Room.fromDocument(doc);
  } on AppwriteException catch (e) {
    if (e.code == 404) return null; // العنصر غير موجود
    if (e.code == 401) throw UnauthorizedException();
    throw AppwriteErrorHandler.handleError(e);
  } catch (e) {
    throw NetworkException('فشل الاتصال');
  }
}
```

---

## 2. إنشاء Client

### ❌ خطأ: إنشاء Client في كل مرة

```dart
class RoomService {
  Future<List<Room>> getRooms() async {
    // إنشاء Client جديد في كل استدعاء ❌
    final client = Client()
      ..setEndpoint('...')
      ..setProject('...');
    
    final databases = Databases(client);
    // ...
  }
}
```

### ✅ صحيح: Singleton Pattern

```dart
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  
  late final Client _client;
  late final Databases _databases;
  
  Future<void> init() async {
    _client = Client()
      ..setEndpoint('...')
      ..setProject('...');
    _databases = Databases(_client);
  }
  
  Databases get databases => _databases;
}
```

---

## 3. عمليات الحذف

### ❌ خطأ: رمي خطأ عند 404

```dart
Future<void> deleteRoom(String id) async {
  try {
    await databases.deleteDocument(...);
  } catch (e) {
    throw Exception('فشل الحذف'); // حتى لو كان 404 ❌
  }
}
```

### ✅ صحيح: معاملة 404 كنجاح

```dart
Future<void> deleteRoom(String id) async {
  try {
    await databases.deleteDocument(...);
  } on AppwriteException catch (e) {
    if (e.code == 404) {
      return; // العنصر محذوف بالفعل ✅
    }
    rethrow;
  }
}
```

---

## 4. جلب القوائم الطويلة

### ❌ خطأ: جلب جميع البيانات دفعة واحدة

```dart
Future<List<Room>> getAllRooms() async {
  // قد يُرجع آلاف السجلات ❌
  final response = await databases.listDocuments(
    databaseId: 'hotel_db',
    collectionId: 'rooms',
  );
  return response.documents.map(...).toList();
}
```

### ✅ صحيح: Pagination

```dart
Future<List<Room>> getRoomsPaginated({
  int limit = 25,
  int offset = 0,
}) async {
  final response = await databases.listDocuments(
    databaseId: 'hotel_db',
    collectionId: 'rooms',
    queries: [
      Query.limit(limit),
      Query.offset(offset),
    ],
  );
  return response.documents.map(...).toList();
}
```

---

## 5. الاستعلامات

### ❌ خطأ: جلب كل البيانات ثم الفلترة محلياً

```dart
Future<List<Room>> getAvailableRooms() async {
  final allRooms = await getAllRooms(); // جلب كل شيء ❌
  return allRooms.where((r) => r.status == 'شاغرة').toList();
}
```

### ✅ صحيح: استخدام Queries

```dart
Future<List<Room>> getAvailableRooms() async {
  final response = await databases.listDocuments(
    databaseId: 'hotel_db',
    collectionId: 'rooms',
    queries: [
      Query.equal('status', 'شاغرة'),
    ],
  );
  return response.documents.map(...).toList();
}
```

---

## 6. المصادقة

### ❌ خطأ: عدم التحقق من الجلسة

```dart
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // بدء التطبيق مباشرة دون التحقق ❌
    return MaterialApp(home: HomePage());
  }
}
```

### ✅ صحيح: التحقق من الجلسة أولاً

```dart
class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isAuthenticated = false;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _checkSession();
  }
  
  Future<void> _checkSession() async {
    try {
      await AppwriteService().account.get();
      setState(() {
        _isAuthenticated = true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return MaterialApp(home: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    
    return MaterialApp(
      home: _isAuthenticated ? HomePage() : LoginPage(),
    );
  }
}
```

---

## 7. Realtime Subscriptions

### ❌ خطأ: عدم إلغاء الاشتراك

```dart
class RoomsScreen extends StatefulWidget {
  @override
  _RoomsScreenState createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  @override
  void initState() {
    super.initState();
    
    // الاشتراك بدون حفظ المرجع ❌
    realtime.subscribe(['databases.hotel_db.collections.rooms.documents']);
  }
  
  // لا يوجد dispose() ❌
}
```

### ✅ صحيح: إدارة Subscription بشكل صحيح

```dart
class _RoomsScreenState extends State<RoomsScreen> {
  RealtimeSubscription? _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscribe();
  }
  
  void _subscribe() {
    final realtime = Realtime(AppwriteService()._client);
    _subscription = realtime.subscribe([
      'databases.hotel_db.collections.rooms.documents',
    ]);
    
    _subscription!.stream.listen((response) {
      // معالجة التحديثات
    });
  }
  
  @override
  void dispose() {
    _subscription?.close(); // ✅ إلغاء الاشتراك
    super.dispose();
  }
}
```

---

## 8. Storage & File Upload

### ❌ خطأ: عدم معالجة أخطاء الرفع

```dart
Future<void> uploadImage(File file) async {
  // رفع بدون معالجة أخطاء ❌
  await storage.createFile(
    bucketId: 'images',
    fileId: ID.unique(),
    file: InputFile.fromPath(path: file.path),
  );
}
```

### ✅ صحيح: معالجة شاملة مع Progress

```dart
Future<String?> uploadImage({
  required File file,
  required ValueChanged<double> onProgress,
}) async {
  try {
    final uploadedFile = await storage.createFile(
      bucketId: 'images',
      fileId: ID.unique(),
      file: InputFile.fromPath(
        path: file.path,
        filename: path.basename(file.path),
      ),
      onProgress: (progress) {
        final percentage = (progress.chunksUploaded * progress.chunkSize) 
            / await file.length();
        onProgress(percentage);
      },
    );
    return uploadedFile.$id;
  } on AppwriteException catch (e) {
    if (e.code == 400) {
      throw Exception('ملف غير صالح');
    }
    if (e.code == 413) {
      throw Exception('حجم الملف كبير جداً');
    }
    throw Exception(AppwriteErrorHandler.handleError(e));
  } catch (e) {
    throw Exception('فشل رفع الملف');
  }
}
```

---

## 9. Offline Support

### ❌ خطأ: عدم التعامل مع فقدان الاتصال

```dart
Future<List<Room>> getRooms() async {
  // فشل مباشر عند انقطاع الإنترنت ❌
  final response = await databases.listDocuments(...);
  return response.documents.map(...).toList();
}
```

### ✅ صحيح: Offline-First Strategy

```dart
Future<List<Room>> getRooms() async {
  try {
    // محاولة جلب من السيرفر
    final response = await databases.listDocuments(...);
    
    // حفظ محلياً
    await localDb.saveRooms(response.documents);
    
    return response.documents.map(...).toList();
  } catch (e) {
    // عند الفشل، جلب من Local Database
    final localRooms = await localDb.getRooms();
    
    if (localRooms.isEmpty) {
      throw Exception('لا توجد بيانات متاحة');
    }
    
    return localRooms;
  }
}
```

---

## 10. Environment Variables

### ❌ خطأ: كشف المفاتيح في الكود

```dart
final client = Client()
  ..setEndpoint('https://cloud.appwrite.io/v1')
  ..setProject('690ff0da0025518570c1'); // ❌ مكشوف في الكود
```

### ✅ صحيح: استخدام .env

```dart
// pubspec.yaml
dependencies:
  flutter_dotenv: ^5.0.2

// .env (لا تضعه في Git!)
APPWRITE_ENDPOINT=https://cloud.appwrite.io/v1
APPWRITE_PROJECT_ID=690ff0da0025518570c1

// main.dart
await dotenv.load();

final client = Client()
  ..setEndpoint(dotenv.env['APPWRITE_ENDPOINT']!)
  ..setProject(dotenv.env['APPWRITE_PROJECT_ID']!);

// .gitignore
.env
```

---

## 11. State Management

### ❌ خطأ: setState() في مكان خاطئ

```dart
class RoomsScreen extends StatefulWidget {
  @override
  _RoomsScreenState createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  List<Room> rooms = [];
  
  @override
  void initState() {
    super.initState();
    loadRooms(); // ❌ setState قد يُستدعى قبل بناء Widget
  }
  
  void loadRooms() async {
    final result = await getRooms();
    setState(() => rooms = result); // ❌ مشكلة
  }
}
```

### ✅ صحيح: استخدام FutureBuilder أو Provider

```dart
// طريقة 1: FutureBuilder
class RoomsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Room>>(
      future: getRooms(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return CircularProgressIndicator();
        }
        if (snapshot.hasError) {
          return Text('خطأ: ${snapshot.error}');
        }
        return ListView.builder(...);
      },
    );
  }
}

// طريقة 2: Provider
class RoomsProvider extends ChangeNotifier {
  List<Room> _rooms = [];
  bool _isLoading = false;
  String? _error;
  
  List<Room> get rooms => _rooms;
  bool get isLoading => _isLoading;
  String? get error => _error;
  
  Future<void> loadRooms() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _rooms = await getRooms();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

---

## 12. Testing

### ❌ خطأ: اختبار بدون Mocking

```dart
test('should get rooms', () async {
  // استدعاء حقيقي للسيرفر ❌
  final rooms = await RoomService().getRooms();
  expect(rooms.length, greaterThan(0));
});
```

### ✅ صحيح: Mock Appwrite

```dart
class MockDatabases extends Mock implements Databases {}

void main() {
  late MockDatabases mockDatabases;
  late RoomRepository repository;
  
  setUp(() {
    mockDatabases = MockDatabases();
    repository = RoomRepository(databases: mockDatabases);
  });
  
  test('should get rooms', () async {
    // ترتيب البيانات التجريبية
    when(mockDatabases.listDocuments(
      databaseId: any,
      collectionId: any,
    )).thenAnswer((_) async => DocumentList(
      total: 2,
      documents: [
        Document(...),
        Document(...),
      ],
    ));
    
    // تنفيذ الاختبار
    final rooms = await repository.getAll();
    
    // التحقق
    expect(rooms.length, 2);
    verify(mockDatabases.listDocuments(
      databaseId: 'hotel_db',
      collectionId: 'rooms',
    )).called(1);
  });
}
```

---

## 📊 جدول المقارنة السريع

| الموضوع | ❌ خطأ | ✅ صحيح |
|---------|--------|---------|
| **Error Handling** | رمي جميع الأخطاء | معالجة حسب النوع |
| **Client** | إنشاء متعدد | Singleton |
| **404 في Delete** | رمي خطأ | اعتبارها نجاح |
| **القوائم** | جلب كل شيء | Pagination |
| **الاستعلامات** | فلترة محلية | Appwrite Queries |
| **المصادقة** | بدء مباشر | التحقق من الجلسة |
| **Realtime** | عدم إلغاء | dispose() صحيح |
| **Upload** | بدون معالجة | Progress + Errors |
| **Offline** | فشل مباشر | Local fallback |
| **Secrets** | في الكود | Environment vars |
| **State** | setState خاطئ | Provider/FutureBuilder |
| **Testing** | استدعاء حقيقي | Mocking |

---

## 🎯 الخلاصة

### الأخطاء الأكثر شيوعاً:

1. ❌ عدم معالجة خطأ 404 في الحذف
2. ❌ إنشاء Client جديد في كل مرة
3. ❌ جلب جميع البيانات دفعة واحدة
4. ❌ عدم التحقق من الجلسة
5. ❌ كشف المفاتيح في الكود

### الحلول الأساسية:

1. ✅ معالجة ذكية للأخطاء حسب النوع
2. ✅ Singleton Pattern للـ Client
3. ✅ Pagination للقوائم الطويلة
4. ✅ التحقق من الجلسة عند البدء
5. ✅ Environment Variables للأسرار

---

**نصيحة ذهبية**: 
> راجع كودك باستمرار وابحث عن هذه الأنماط. إصلاحها سيحسّن الأداء والاستقرار بشكل كبير!

---

**تاريخ التحديث**: 2026-01-28  
**الإصدار**: 1.0
