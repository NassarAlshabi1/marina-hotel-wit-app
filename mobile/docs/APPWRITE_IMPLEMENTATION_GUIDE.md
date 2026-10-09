# 🚀 Appwrite Best Practices - Implementation Guide

تم تطبيق أفضل ممارسات Appwrite + Flutter على هذا التطبيق.

## 📦 الملفات الجديدة المُضافة

### 1. Connection State Manager
**الملف:** `lib/services/connection_state_manager.dart`

**الاستخدام:**
```dart
import 'package:marina_hotel/services/connection_state_manager.dart';

// تهيئة
await ConnectionStateManager().init();

// الاستماع للتغييرات
ConnectionStateManager().statusStream.listen((status) {
  print('Connection status: $status');
});

// في الـ UI
Consumer<ConnectionStateManager>(
  builder: (context, connection, child) {
    return Text(
      connection.isOnline ? 'متصل' : 'غير متصل',
      style: TextStyle(
        color: connection.isOnline ? Colors.green : Colors.red,
      ),
    );
  },
)
```

---

### 2. Advanced Query Builder
**الملف:** `lib/services/advanced_query_builder.dart`

**الاستخدام:**
```dart
import 'package:marina_hotel/services/advanced_query_builder.dart';

// بناء استعلام معقد
final queries = AdvancedQueryBuilder()
    .where('status', 'شاغرة')
    .whereBetween('price', 10000, 20000)
    .search('room_number', '101')
    .orderBy('price', desc: false)
    .limit(25)
    .offset(0)
    .build();

// استخدام الاستعلام
final rooms = await appwriteService.listDocuments(
  collectionId: 'rooms',
  queries: queries,
);
```

---

### 3. Batch Operations Service
**الملف:** `lib/services/batch_operations_service.dart`

**الاستخدام:**
```dart
import 'package:marina_hotel/services/batch_operations_service.dart';

final batchService = BatchOperationsService();

// حذف عدة غرف
final result = await batchService.deleteDocuments(
  databaseId: 'hotel_db',
  collectionId: 'rooms',
  documentIds: ['id1', 'id2', 'id3'],
  parallel: true,
);

print('نجح: ${result.successful}، فشل: ${result.failed}');
print('معدل النجاح: ${(result.successRate * 100).toStringAsFixed(1)}%');

// إنشاء عدة غرف
final createResult = await batchService.createDocuments(
  databaseId: 'hotel_db',
  collectionId: 'rooms',
  documents: [
    {'room_number': '601', 'type': 'سرير فردي', 'price': 8000, 'status': 'شاغرة'},
    {'room_number': '602', 'type': 'سرير عائلي', 'price': 12000, 'status': 'شاغرة'},
  ],
);
```

---

### 4. Room Repository
**الملف:** `lib/repositories/room_repository.dart`

**الاستخدام:**
```dart
import 'package:marina_hotel/repositories/room_repository.dart';

final roomRepository = AppwriteRoomRepository();

// الحصول على غرفة
final room = await roomRepository.getById('room_id');

// الحصول على الغرف الشاغرة
final availableRooms = await roomRepository.getAvailable();

// البحث
final searchResults = await roomRepository.search('101');

// البحث بالسعر
final roomsInRange = await roomRepository.getByPriceRange(10000, 15000);

// Pagination
final page1 = await roomRepository.getPaginated(limit: 25, offset: 0);
final page2 = await roomRepository.getPaginated(limit: 25, offset: 25);

// إحصائيات
final stats = await roomRepository.getStatistics();
print(stats); // عرض إحصائيات كاملة
```

---

### 5. Realtime Rooms Provider
**الملف:** `lib/providers/realtime_rooms_provider.dart`

**الاستخدام:**
```dart
import 'package:marina_hotel/providers/realtime_rooms_provider.dart';
import 'package:provider/provider.dart';

// في main.dart
ChangeNotifierProvider(
  create: (_) => RealTimeRoomsProvider(
    repository: AppwriteRoomRepository(),
    realtimeService: AppwriteRealtimeService(),
  )..subscribe(),
),

// في الـ UI
class RoomsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<RealTimeRoomsProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return CircularProgressIndicator();
        }

        if (provider.error != null) {
          return Text('خطأ: ${provider.error}');
        }

        return ListView.builder(
          itemCount: provider.roomCount,
          itemBuilder: (context, index) {
            final room = provider.rooms[index];
            return ListTile(
              title: Text(room.roomNumber),
              subtitle: Text('${room.type} - ${room.price} ريال'),
              trailing: Text(room.status),
            );
          },
        );
      },
    );
  }
}
```

---

## 🔧 كيفية التكامل

### 1. إضافة Dependencies

في `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  appwrite: ^11.0.0
  provider: ^6.0.0
  connectivity_plus: ^5.0.0
```

### 2. تهيئة في main.dart

```dart
import 'package:marina_hotel/services/connection_state_manager.dart';
import 'package:marina_hotel/services/appwrite_service.dart';
import 'package:marina_hotel/providers/realtime_rooms_provider.dart';
import 'package:provider/provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة Appwrite
  await AppwriteService().initialize();
  
  // تهيئة Connection Manager
  await ConnectionStateManager().init();
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectionStateManager()),
        ChangeNotifierProvider(
          create: (_) => RealTimeRoomsProvider(
            repository: AppwriteRoomRepository(),
            realtimeService: AppwriteRealtimeService(),
          )..subscribe(),
        ),
      ],
      child: MyApp(),
    ),
  );
}
```

### 3. مثال شامل: صفحة الغرف

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:marina_hotel/providers/realtime_rooms_provider.dart';
import 'package:marina_hotel/services/connection_state_manager.dart';

class RoomsScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('الغرف'),
        backgroundColor: context.watch<ConnectionStateManager>().isOnline
            ? Colors.green
            : Colors.red,
        actions: [
          // عرض حالة الاتصال
          Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: Text(
                context.watch<ConnectionStateManager>().getStatusMessage(),
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: Consumer<RealTimeRoomsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red),
                  SizedBox(height: 16),
                  Text('خطأ: ${provider.error}'),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: provider.refresh,
                    child: Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          }

          if (provider.roomCount == 0) {
            return Center(child: Text('لا توجد غرف'));
          }

          return Column(
            children: [
              // إحصائيات سريعة
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatCard(
                      title: 'الإجمالي',
                      value: '${provider.roomCount}',
                      color: Colors.blue,
                    ),
                    _StatCard(
                      title: 'شاغرة',
                      value: '${provider.availableRooms.length}',
                      color: Colors.green,
                    ),
                    _StatCard(
                      title: 'محجوزة',
                      value: '${provider.occupiedRooms.length}',
                      color: Colors.orange,
                    ),
                  ],
                ),
              ),
              
              Divider(),
              
              // قائمة الغرف
              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.refresh,
                  child: ListView.builder(
                    itemCount: provider.roomCount,
                    itemBuilder: (context, index) {
                      final room = provider.rooms[index];
                      return Card(
                        margin: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: room.status == 'شاغرة'
                                ? Colors.green
                                : Colors.orange,
                            child: Text(
                              room.roomNumber,
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(room.type),
                          subtitle: Text('${room.price.toStringAsFixed(0)} ريال'),
                          trailing: Chip(
                            label: Text(room.status),
                            backgroundColor: room.status == 'شاغرة'
                                ? Colors.green.shade100
                                : Colors.orange.shade100,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
```

---

## ✅ المزايا

### 1. Connection State Manager
- ✅ مراقبة حالة الاتصال تلقائياً
- ✅ إشعارات فورية عند تغيير الحالة
- ✅ فحص دوري كل 30 ثانية
- ✅ تكامل سهل مع UI

### 2. Advanced Query Builder
- ✅ Fluent API سهل الاستخدام
- ✅ دعم جميع أنواع الاستعلامات
- ✅ Type-safe queries
- ✅ قابل للتوسع

### 3. Batch Operations
- ✅ تنفيذ متوازي للسرعة
- ✅ معالجة أخطاء شاملة
- ✅ إحصائيات مفصلة
- ✅ دعم عمليات مختلطة

### 4. Repository Pattern
- ✅ فصل منطق البيانات عن UI
- ✅ سهولة الاختبار (Testable)
- ✅ قابل للاستبدال (Mockable)
- ✅ معالجة أخطاء موحدة

### 5. Realtime Provider
- ✅ تحديثات فورية تلقائية
- ✅ إدارة حالة محسّنة
- ✅ دعم Optimistic Updates
- ✅ بحث محلي سريع

---

## 📚 المراجع

راجع الأدلة الشاملة في:
- `docs/appwrite-guides/APPWRITE_FLUTTER_BEST_PRACTICES.md`
- `docs/appwrite-guides/APPWRITE_FLUTTER_ADVANCED_EXAMPLES.md`
- `docs/appwrite-guides/APPWRITE_FLUTTER_COMMON_MISTAKES.md`

---

**تاريخ الإنشاء**: 2026-01-28  
**الإصدار**: 1.0
