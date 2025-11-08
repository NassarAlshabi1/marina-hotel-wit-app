# 💡 Supabase Examples & Code Snippets
# أمثلة وشيفرات جاهزة لـ Supabase

<div dir="rtl">

## مجموعة شاملة من الأمثلة العملية
## Complete collection of practical examples

</div>

---

## 📋 جدول المحتويات | Table of Contents

1. [Authentication](#authentication)
2. [Sync Operations](#sync-operations)
3. [Direct Database Access](#direct-database-access)
4. [Edge Functions](#edge-functions)
5. [Error Handling](#error-handling)
6. [Advanced Patterns](#advanced-patterns)

---

## 🔐 Authentication

### تسجيل الدخول | Sign In

```dart
import 'package:marina_hotel/utils/supabase_config.dart';

// Basic Sign In
Future<void> signIn() async {
  try {
    final response = await SupabaseConfig.signInWithEmail(
      email: 'user@example.com',
      password: 'password123',
    );
    
    if (response.user != null) {
      print('✅ Signed in as ${response.user!.email}');
      print('User ID: ${response.user!.id}');
      print('JWT Token: ${response.session?.accessToken}');
    }
  } catch (e) {
    print('❌ Sign in failed: $e');
  }
}

// Sign In with Error Handling
Future<bool> signInSafe(String email, String password) async {
  try {
    final response = await SupabaseConfig.signInWithEmail(
      email: email,
      password: password,
    );
    return response.user != null;
  } on AuthException catch (e) {
    print('Auth error: ${e.message}');
    return false;
  } catch (e) {
    print('Unknown error: $e');
    return false;
  }
}
```

### التسجيل | Sign Up

```dart
// Basic Sign Up
Future<void> signUp() async {
  try {
    final response = await SupabaseConfig.signUpWithEmail(
      email: 'newuser@example.com',
      password: 'securepassword123',
      metadata: {
        'name': 'John Doe',
        'role': 'manager',
      },
    );
    
    if (response.user != null) {
      print('✅ User created: ${response.user!.email}');
    }
  } catch (e) {
    print('❌ Sign up failed: $e');
  }
}

// Sign Up with Validation
Future<bool> signUpWithValidation({
  required String email,
  required String password,
  required String confirmPassword,
  required String name,
}) async {
  // Validation
  if (password != confirmPassword) {
    print('❌ Passwords do not match');
    return false;
  }
  
  if (password.length < 8) {
    print('❌ Password must be at least 8 characters');
    return false;
  }
  
  try {
    final response = await SupabaseConfig.signUpWithEmail(
      email: email,
      password: password,
      metadata: {'name': name},
    );
    
    return response.user != null;
  } catch (e) {
    print('❌ Sign up failed: $e');
    return false;
  }
}
```

### تسجيل الخروج | Sign Out

```dart
// Sign Out
Future<void> signOut() async {
  try {
    await SupabaseConfig.signOut();
    print('✅ Signed out successfully');
  } catch (e) {
    print('❌ Sign out failed: $e');
  }
}
```

### التحقق من حالة تسجيل الدخول | Check Login Status

```dart
// Check if user is logged in
bool isUserLoggedIn() {
  return SupabaseConfig.isLoggedIn;
}

// Get current user
User? getCurrentUser() {
  return SupabaseConfig.currentUser;
}

// Get current user email
String? getCurrentUserEmail() {
  return SupabaseConfig.currentUser?.email;
}

// Listen to auth state changes
void listenToAuthChanges() {
  SupabaseConfig.authStateChanges.listen((event) {
    final session = event.session;
    if (session != null) {
      print('✅ User signed in: ${session.user.email}');
    } else {
      print('❌ User signed out');
    }
  });
}
```

---

## 🔄 Sync Operations

### المزامنة الأساسية | Basic Sync

```dart
import 'package:marina_hotel/services/supabase_sync_service.dart';

// Basic Sync
Future<void> basicSync(WidgetRef ref) async {
  final syncService = ref.read(supabaseSyncServiceProvider);
  
  try {
    await syncService.runSync();
    print('✅ Sync completed successfully');
  } catch (e) {
    print('❌ Sync failed: $e');
  }
}

// Sync with Status Updates
Future<void> syncWithStatus(WidgetRef ref) async {
  final syncService = ref.read(supabaseSyncServiceProvider);
  
  // Listen to sync status
  final subscription = ref.listen(
    supabaseSyncStatusProvider,
    (previous, next) {
      next.when(
        data: (status) {
          switch (status) {
            case SyncStatus.pushing:
              print('📤 Pushing local changes...');
              break;
            case SyncStatus.pulling:
              print('📥 Pulling remote changes...');
              break;
            case SyncStatus.idle:
              print('✅ Sync completed');
              break;
            case SyncStatus.error:
              print('❌ Sync error occurred');
              break;
          }
        },
        loading: () => print('⏳ Sync loading...'),
        error: (error, stack) => print('❌ Sync error: $error'),
      );
    },
  );
  
  await syncService.runSync();
}
```

### المزامنة التلقائية | Auto Sync

```dart
// Auto sync every 5 minutes
class AutoSyncService {
  Timer? _timer;
  final WidgetRef ref;
  
  AutoSyncService(this.ref);
  
  void startAutoSync() {
    _timer = Timer.periodic(Duration(minutes: 5), (timer) async {
      print('🔄 Auto sync triggered');
      final syncService = ref.read(supabaseSyncServiceProvider);
      try {
        await syncService.runSync();
        print('✅ Auto sync completed');
      } catch (e) {
        print('❌ Auto sync failed: $e');
      }
    });
  }
  
  void stopAutoSync() {
    _timer?.cancel();
    _timer = null;
    print('⏸️ Auto sync stopped');
  }
}

// Usage
final autoSync = AutoSyncService(ref);
autoSync.startAutoSync();

// Stop when done
autoSync.stopAutoSync();
```

### المزامنة الانتقائية | Selective Sync

```dart
// Sync only when connected to WiFi
Future<void> syncOnWifiOnly(WidgetRef ref) async {
  final connectivity = await Connectivity().checkConnectivity();
  
  if (connectivity == ConnectivityResult.wifi) {
    final syncService = ref.read(supabaseSyncServiceProvider);
    await syncService.runSync();
    print('✅ Synced on WiFi');
  } else {
    print('⏭️ Skipped sync (not on WiFi)');
  }
}

// Sync with retry logic
Future<void> syncWithRetry(WidgetRef ref, {int maxRetries = 3}) async {
  final syncService = ref.read(supabaseSyncServiceProvider);
  
  for (int i = 0; i < maxRetries; i++) {
    try {
      await syncService.runSync();
      print('✅ Sync successful on attempt ${i + 1}');
      return;
    } catch (e) {
      print('❌ Sync attempt ${i + 1} failed: $e');
      if (i < maxRetries - 1) {
        await Future.delayed(Duration(seconds: 2 * (i + 1)));
      }
    }
  }
  
  print('❌ Sync failed after $maxRetries attempts');
}
```

---

## 🗄️ Direct Database Access

### قراءة البيانات | Reading Data

```dart
import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

// Get all rooms
Future<List<Map<String, dynamic>>> getAllRooms() async {
  final response = await supabase
    .from('rooms')
    .select()
    .is_('deleted_at', null)
    .order('room_number');
  
  return List<Map<String, dynamic>>.from(response);
}

// Get room by number
Future<Map<String, dynamic>?> getRoomByNumber(String roomNumber) async {
  final response = await supabase
    .from('rooms')
    .select()
    .eq('room_number', roomNumber)
    .is_('deleted_at', null)
    .maybeSingle();
  
  return response;
}

// Get available rooms
Future<List<Map<String, dynamic>>> getAvailableRooms() async {
  final response = await supabase
    .from('rooms')
    .select()
    .eq('status', 'شاغرة')
    .is_('deleted_at', null)
    .order('room_number');
  
  return List<Map<String, dynamic>>.from(response);
}

// Get bookings with date range
Future<List<Map<String, dynamic>>> getBookingsByDateRange({
  required DateTime startDate,
  required DateTime endDate,
}) async {
  final response = await supabase
    .from('bookings')
    .select()
    .gte('checkin_date', startDate.toIso8601String())
    .lte('checkout_date', endDate.toIso8601String())
    .is_('deleted_at', null)
    .order('checkin_date');
  
  return List<Map<String, dynamic>>.from(response);
}

// Get with joins
Future<List<Map<String, dynamic>>> getBookingsWithRoomInfo() async {
  final response = await supabase
    .from('bookings')
    .select('*, rooms(*)')
    .is_('deleted_at', null)
    .order('checkin_date', ascending: false);
  
  return List<Map<String, dynamic>>.from(response);
}
```

### كتابة البيانات | Writing Data

```dart
// Insert a room
Future<void> insertRoom({
  required String roomNumber,
  required String type,
  required double price,
}) async {
  await supabase.from('rooms').insert({
    'room_number': roomNumber,
    'type': type,
    'price': price,
    'status': 'شاغرة',
    'local_uuid': Uuid().v4(),
    'origin': 'server',
  });
  
  print('✅ Room inserted');
}

// Update a room
Future<void> updateRoom({
  required String roomNumber,
  double? price,
  String? status,
}) async {
  final updates = <String, dynamic>{};
  if (price != null) updates['price'] = price;
  if (status != null) updates['status'] = status;
  
  await supabase
    .from('rooms')
    .update(updates)
    .eq('room_number', roomNumber);
  
  print('✅ Room updated');
}

// Delete (soft delete)
Future<void> deleteRoom(String roomNumber) async {
  await supabase
    .from('rooms')
    .update({'deleted_at': DateTime.now().toIso8601String()})
    .eq('room_number', roomNumber);
  
  print('✅ Room deleted (soft)');
}

// Batch insert
Future<void> insertMultipleRooms(List<Map<String, dynamic>> rooms) async {
  await supabase.from('rooms').insert(rooms);
  print('✅ ${rooms.length} rooms inserted');
}
```

### استعلامات متقدمة | Advanced Queries

```dart
// Count records
Future<int> countAvailableRooms() async {
  final response = await supabase
    .from('rooms')
    .select('id', const FetchOptions(count: CountOption.exact))
    .eq('status', 'شاغرة')
    .is_('deleted_at', null);
  
  return response.count ?? 0;
}

// Search with text
Future<List<Map<String, dynamic>>> searchGuestsByName(String query) async {
  final response = await supabase
    .from('bookings')
    .select()
    .ilike('guest_name', '%$query%')
    .is_('deleted_at', null)
    .limit(10);
  
  return List<Map<String, dynamic>>.from(response);
}

// Aggregate data
Future<Map<String, dynamic>> getRoomStatistics() async {
  final allRooms = await supabase
    .from('rooms')
    .select()
    .is_('deleted_at', null);
  
  final available = allRooms.where((r) => r['status'] == 'شاغرة').length;
  final occupied = allRooms.where((r) => r['status'] == 'مشغولة').length;
  final maintenance = allRooms.where((r) => r['status'] == 'صيانة').length;
  
  return {
    'total': allRooms.length,
    'available': available,
    'occupied': occupied,
    'maintenance': maintenance,
  };
}
```

---

## ⚡ Edge Functions

### استدعاء Functions | Calling Functions

```dart
// Call sync-push
Future<Map<String, dynamic>> callSyncPush(
  List<Map<String, dynamic>> changes,
) async {
  final response = await supabase.functions.invoke(
    'sync-push',
    body: {'changes': changes},
  );
  
  if (response.status == 200) {
    return response.data as Map<String, dynamic>;
  } else {
    throw Exception('Push failed: ${response.data}');
  }
}

// Call sync-pull
Future<Map<String, dynamic>> callSyncPull(String lastPullTs) async {
  final response = await supabase.functions.invoke(
    'sync-pull',
    body: {'last_pull_ts': lastPullTs},
  );
  
  if (response.status == 200) {
    return response.data as Map<String, dynamic>;
  } else {
    throw Exception('Pull failed: ${response.data}');
  }
}

// Call with timeout
Future<Map<String, dynamic>> callFunctionWithTimeout(
  String functionName,
  Map<String, dynamic> body,
) async {
  final response = await supabase.functions
    .invoke(functionName, body: body)
    .timeout(Duration(seconds: 30));
  
  return response.data as Map<String, dynamic>;
}
```

### إنشاء Custom Function | Creating Custom Function

```typescript
// supabase/functions/get-statistics/index.ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.38.4'

serve(async (req) => {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get statistics
    const { data: rooms } = await supabase
      .from('rooms')
      .select('*')
      .is('deleted_at', null)

    const { data: bookings } = await supabase
      .from('bookings')
      .select('*')
      .is('deleted_at', null)

    const stats = {
      total_rooms: rooms?.length || 0,
      total_bookings: bookings?.length || 0,
      available_rooms: rooms?.filter(r => r.status === 'شاغرة').length || 0,
    }

    return new Response(JSON.stringify(stats), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})
```

```dart
// استخدام Function
Future<Map<String, dynamic>> getStatistics() async {
  final response = await supabase.functions.invoke('get-statistics');
  return response.data as Map<String, dynamic>;
}
```

---

## 🚨 Error Handling

### معالجة أخطاء شاملة | Comprehensive Error Handling

```dart
// Error handling wrapper
Future<T?> safeSupabaseCall<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PostgrestException catch (e) {
    print('Database error: ${e.message}');
    print('Code: ${e.code}');
    print('Details: ${e.details}');
    return null;
  } on FunctionException catch (e) {
    print('Function error: ${e.status} - ${e.details}');
    return null;
  } on AuthException catch (e) {
    print('Auth error: ${e.message}');
    return null;
  } catch (e) {
    print('Unknown error: $e');
    return null;
  }
}

// Usage
final rooms = await safeSupabaseCall(() => getAllRooms());
if (rooms != null) {
  print('Got ${rooms.length} rooms');
} else {
  print('Failed to get rooms');
}
```

### Error Recovery | استرجاع بعد الأخطاء

```dart
// Retry with exponential backoff
Future<T?> retryOperation<T>({
  required Future<T> Function() operation,
  int maxRetries = 3,
  Duration initialDelay = const Duration(seconds: 1),
}) async {
  int retries = 0;
  Duration delay = initialDelay;
  
  while (retries < maxRetries) {
    try {
      return await operation();
    } catch (e) {
      retries++;
      print('Attempt $retries failed: $e');
      
      if (retries >= maxRetries) {
        print('Max retries reached');
        rethrow;
      }
      
      await Future.delayed(delay);
      delay *= 2; // Exponential backoff
    }
  }
  
  return null;
}

// Usage
final result = await retryOperation(
  operation: () => supabase.from('rooms').select(),
  maxRetries: 5,
);
```

---

## 🎯 Advanced Patterns

### Realtime Subscriptions

```dart
// Subscribe to rooms changes
RealtimeChannel subscribeToRooms() {
  final channel = supabase
    .channel('rooms_channel')
    .on(
      RealtimeListenTypes.postgresChanges,
      ChannelFilter(
        event: '*',
        schema: 'public',
        table: 'rooms',
      ),
      (payload) {
        print('Change received: ${payload.eventType}');
        print('Data: ${payload.newRecord}');
      },
    )
    .subscribe();
  
  return channel;
}

// Unsubscribe
Future<void> unsubscribe(RealtimeChannel channel) async {
  await supabase.removeChannel(channel);
}
```

### Batch Operations

```dart
// Process in batches
Future<void> processBatch(
  List<Map<String, dynamic>> items,
  int batchSize,
) async {
  for (int i = 0; i < items.length; i += batchSize) {
    final end = (i + batchSize < items.length) 
      ? i + batchSize 
      : items.length;
    final batch = items.sublist(i, end);
    
    await supabase.from('rooms').insert(batch);
    print('Processed batch ${i ~/ batchSize + 1}');
  }
}
```

### Transactions Pattern

```dart
// Simulated transaction (Supabase doesn't have explicit transactions in client)
Future<bool> transferPayment({
  required int fromBookingId,
  required int toBookingId,
  required double amount,
}) async {
  try {
    // 1. Create payment for target
    await supabase.from('payments').insert({
      'server_booking_id': toBookingId,
      'amount': amount,
      'payment_method': 'تحويل',
    });
    
    // 2. Create expense for source
    await supabase.from('expenses').insert({
      'expense_type': 'other',
      'related_id': fromBookingId,
      'amount': amount,
      'description': 'تحويل إلى حجز $toBookingId',
    });
    
    return true;
  } catch (e) {
    print('Transaction failed: $e');
    // هنا يمكنك إضافة منطق rollback يدوي
    return false;
  }
}
```

---

## 📊 Performance Optimization

```dart
// Cache frequently used data
class DataCache {
  static final Map<String, dynamic> _cache = {};
  static final Map<String, DateTime> _cacheTime = {};
  
  static Future<T> getOrFetch<T>({
    required String key,
    required Future<T> Function() fetcher,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    // Check if cached and not expired
    if (_cache.containsKey(key) && _cacheTime.containsKey(key)) {
      final age = DateTime.now().difference(_cacheTime[key]!);
      if (age < maxAge) {
        return _cache[key] as T;
      }
    }
    
    // Fetch new data
    final data = await fetcher();
    _cache[key] = data;
    _cacheTime[key] = DateTime.now();
    
    return data;
  }
  
  static void clear() {
    _cache.clear();
    _cacheTime.clear();
  }
}

// Usage
final rooms = await DataCache.getOrFetch(
  key: 'all_rooms',
  fetcher: () => getAllRooms(),
  maxAge: Duration(minutes: 10),
);
```

---

<div align="center">

## 🎉 المزيد من الأمثلة قريباً!
## More Examples Coming Soon!

</div>

---

**آخر تحديث | Last Updated:** 2024-11-04  
**الإصدار | Version:** 1.0.0
