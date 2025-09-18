# وثائق API المزامنة - نظام إدارة الفندق

## 📡 نظرة عامة على API المزامنة

يوفر نظام المزامنة API شامل لضمان تحديث البيانات عبر جميع الأجهزة في الوقت الفعلي مع دعم العمل بدون إنترنت.

### المميزات الرئيسية
- **Real-time Sync**: مزامنة فورية للتحديثات
- **Offline Support**: عمل كامل بدون إنترنت
- **Conflict Resolution**: حل تلقائي للتعارضات
- **Cross-device**: مزامنة عبر أجهزة متعددة
- **Security**: تشفير البيانات أثناء النقل

---

## 🔧 إعداد النظام

### تهيئة Sync Manager

```javascript
// تهيئة مدير المزامنة
const syncManager = new SyncManager({
    endpoint: 'https://your-api.supabase.co',
    apiKey: 'your-api-key',
    deviceId: 'unique-device-id',
    syncInterval: 30000, // 30 ثانية
    retryAttempts: 3,
    enableOfflineMode: true
});

// بدء المزامنة
await syncManager.initialize();
```

### تكوين قاعدة البيانات

```sql
-- إنشاء جدول تتبع التغييرات
CREATE TABLE sync_changes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_name TEXT NOT NULL,
    record_id TEXT NOT NULL,
    operation TEXT NOT NULL, -- 'create', 'update', 'delete'
    data JSONB,
    device_id TEXT NOT NULL,
    timestamp TIMESTAMPTZ DEFAULT NOW(),
    synced BOOLEAN DEFAULT FALSE,
    version INTEGER DEFAULT 1
);

-- إنشاء فهارس للأداء
CREATE INDEX idx_sync_changes_table ON sync_changes(table_name);
CREATE INDEX idx_sync_changes_device ON sync_changes(device_id);
CREATE INDEX idx_sync_changes_timestamp ON sync_changes(timestamp);
CREATE INDEX idx_sync_changes_synced ON sync_changes(synced);
```

---

## 📊 عمليات البيانات الأساسية

### إضافة سجل جديد

```javascript
// إضافة غرفة جديدة
const newRoom = {
    room_number: '101',
    type: 'سرير عائلي',
    price: 15000,
    status: 'شاغرة'
};

// إضافة مع المزامنة
const changeId = await syncManager.create('rooms', newRoom);
console.log('Change ID:', changeId);
```

### تحديث سجل موجود

```javascript
// تحديث بيانات الغرفة
const updatedRoom = {
    room_number: '101',
    type: 'سرير عائلي',
    price: 18000, // سعر جديد
    status: 'شاغرة'
};

// تحديث مع المزامنة
const changeId = await syncManager.update('rooms', '101', updatedRoom);
```

### حذف سجل

```javascript
// حذف غرفة
const changeId = await syncManager.delete('rooms', '101');
```

---

## 🔄 آلية المزامنة

### المزامنة التلقائية

```javascript
// بدء المزامنة التلقائية
syncManager.startAutoSync();

// إيقاف المزامنة التلقائية
syncManager.stopAutoSync();

// مزامنة فورية
await syncManager.forceSync();
```

### مراقبة حالة المزامنة

```javascript
// الاستماع لأحداث المزامنة
syncManager.on('syncStart', () => {
    console.log('بدأت المزامنة...');
});

syncManager.on('syncComplete', (result) => {
    console.log('اكتملت المزامنة:', result);
});

syncManager.on('syncError', (error) => {
    console.error('خطأ في المزامنة:', error);
});

syncManager.on('conflictDetected', (conflict) => {
    console.warn('تم اكتشاف تعارض:', conflict);
});
```

### الحصول على حالة المزامنة

```javascript
const status = syncManager.getSyncStatus();
console.log({
    isOnline: status.isOnline,
    pendingChanges: status.pendingChanges,
    lastSyncTime: status.lastSyncTime,
    deviceId: status.deviceId
});
```

---

## 🔀 حل التعارضات

### استراتيجيات حل التعارضات

```javascript
// تكوين استراتيجية حل التعارضات
syncManager.setConflictResolution({
    strategy: 'last-write-wins', // أو 'manual', 'merge'
    
    // دالة مخصصة لحل التعارضات
    resolver: (localData, remoteData, conflict) => {
        // منطق مخصص لحل التعارض
        if (conflict.field === 'price') {
            // استخدام السعر الأعلى
            return Math.max(localData.price, remoteData.price);
        }
        
        // استخدام البيانات الأحدث
        return new Date(localData.updated_at) > new Date(remoteData.updated_at) 
            ? localData : remoteData;
    }
});
```

### معالجة التعارضات يدوياً

```javascript
// الحصول على التعارضات المعلقة
const conflicts = await syncManager.getPendingConflicts();

conflicts.forEach(async (conflict) => {
    // عرض التعارض للمستخدم
    const resolution = await showConflictDialog(conflict);
    
    // تطبيق الحل
    await syncManager.resolveConflict(conflict.id, resolution);
});
```

---

## 📱 دعم العمل بدون إنترنت

### تخزين التغييرات محلياً

```javascript
// التحقق من حالة الاتصال
if (!navigator.onLine) {
    console.log('العمل في وضع عدم الاتصال');
    
    // التغييرات ستحفظ محلياً
    await syncManager.create('bookings', newBooking);
    
    // عرض رسالة للمستخدم
    showNotification('تم الحفظ محلياً - سيتم المزامنة عند الاتصال');
}
```

### مزامنة عند العودة للاتصال

```javascript
// الاستماع لأحداث الشبكة
window.addEventListener('online', async () => {
    console.log('تم الاتصال بالإنترنت');
    
    // مزامنة التغييرات المعلقة
    await syncManager.syncPendingChanges();
    
    showNotification('تم الاتصال - جاري المزامنة...');
});

window.addEventListener('offline', () => {
    console.log('انقطع الاتصال');
    showNotification('وضع عدم الاتصال - سيتم الحفظ محلياً');
});
```

---

## 🔐 الأمان والتشفير

### تشفير البيانات

```javascript
// تكوين التشفير
syncManager.setEncryption({
    enabled: true,
    algorithm: 'AES-256-GCM',
    key: 'your-encryption-key'
});

// البيانات ستشفر تلقائياً قبل الإرسال
await syncManager.create('payments', sensitivePaymentData);
```

### المصادقة والتخويل

```javascript
// تعيين رمز المصادقة
syncManager.setAuthToken('jwt-token');

// تجديد الرمز تلقائياً
syncManager.setTokenRefreshCallback(async () => {
    const newToken = await refreshAuthToken();
    return newToken;
});
```

---

## 📊 مراقبة الأداء

### إحصائيات المزامنة

```javascript
// الحصول على إحصائيات مفصلة
const stats = await syncManager.getStats();

console.log({
    totalSyncs: stats.totalSyncs,
    successfulSyncs: stats.successfulSyncs,
    failedSyncs: stats.failedSyncs,
    averageSyncTime: stats.averageSyncTime,
    dataTransferred: stats.dataTransferred,
    conflictsResolved: stats.conflictsResolved
});
```

### تسجيل الأحداث

```javascript
// تفعيل التسجيل المفصل
syncManager.setLogLevel('debug');

// تخصيص دالة التسجيل
syncManager.setLogger((level, message, data) => {
    console.log(`[${level}] ${message}`, data);
    
    // إرسال للخادم للمراقبة
    if (level === 'error') {
        sendErrorToServer(message, data);
    }
});
```

---

## 🔧 تكوينات متقدمة

### تحسين الأداء

```javascript
// تكوين متقدم للأداء
syncManager.configure({
    // حجم الدفعة للمزامنة
    batchSize: 50,
    
    // مهلة الاتصال
    timeout: 30000,
    
    // ضغط البيانات
    compression: true,
    
    // تخزين مؤقت ذكي
    smartCaching: true,
    
    // مزامنة تدريجية
    incrementalSync: true
});
```

### تخصيص المزامنة لكل جدول

```javascript
// تكوين مخصص لكل جدول
syncManager.setTableConfig('rooms', {
    syncPriority: 'high',
    conflictResolution: 'last-write-wins',
    enableRealtime: true,
    cacheTimeout: 300000 // 5 دقائق
});

syncManager.setTableConfig('reports', {
    syncPriority: 'low',
    conflictResolution: 'manual',
    enableRealtime: false,
    cacheTimeout: 3600000 // ساعة واحدة
});
```

---

## 🧪 اختبار النظام

### اختبار المزامنة

```javascript
// اختبار أساسي للمزامنة
async function testSync() {
    try {
        // إضافة بيانات تجريبية
        const testData = { name: 'Test Room', price: 1000 };
        const changeId = await syncManager.create('rooms', testData);
        
        // انتظار المزامنة
        await syncManager.waitForSync(changeId);
        
        console.log('✅ اختبار المزامنة نجح');
    } catch (error) {
        console.error('❌ فشل اختبار المزامنة:', error);
    }
}

// اختبار العمل بدون إنترنت
async function testOfflineMode() {
    // محاكاة انقطاع الاتصال
    syncManager.simulateOffline(true);
    
    // إضافة بيانات
    await syncManager.create('bookings', testBooking);
    
    // التحقق من التخزين المحلي
    const pendingChanges = syncManager.getPendingChanges();
    console.log('التغييرات المعلقة:', pendingChanges.length);
    
    // محاكاة العودة للاتصال
    syncManager.simulateOffline(false);
    
    // انتظار المزامنة
    await syncManager.forceSync();
}
```

---

## 📋 أمثلة عملية

### مثال شامل: إدارة الحجوزات

```javascript
class BookingManager {
    constructor(syncManager) {
        this.sync = syncManager;
    }
    
    async createBooking(bookingData) {
        try {
            // التحقق من صحة البيانات
            this.validateBookingData(bookingData);
            
            // إضافة معرف فريد
            bookingData.id = this.generateId();
            bookingData.created_at = new Date().toISOString();
            
            // حفظ مع المزامنة
            const changeId = await this.sync.create('bookings', bookingData);
            
            // تحديث حالة الغرفة
            await this.updateRoomStatus(bookingData.room_number, 'محجوزة');
            
            // إرسال إشعار
            this.sendNotification('تم إنشاء حجز جديد', bookingData);
            
            return { success: true, changeId, booking: bookingData };
            
        } catch (error) {
            console.error('خطأ في إنشاء الحجز:', error);
            throw error;
        }
    }
    
    async updateBooking(bookingId, updates) {
        try {
            // الحصول على الحجز الحالي
            const currentBooking = await this.getBooking(bookingId);
            
            // دمج التحديثات
            const updatedBooking = { ...currentBooking, ...updates };
            updatedBooking.updated_at = new Date().toISOString();
            
            // حفظ التحديثات
            const changeId = await this.sync.update('bookings', bookingId, updatedBooking);
            
            return { success: true, changeId, booking: updatedBooking };
            
        } catch (error) {
            console.error('خطأ في تحديث الحجز:', error);
            throw error;
        }
    }
    
    async cancelBooking(bookingId) {
        try {
            const booking = await this.getBooking(bookingId);
            
            // تحديث حالة الحجز
            booking.status = 'ملغي';
            booking.cancelled_at = new Date().toISOString();
            
            // حفظ التحديث
            await this.sync.update('bookings', bookingId, booking);
            
            // تحرير الغرفة
            await this.updateRoomStatus(booking.room_number, 'شاغرة');
            
            return { success: true };
            
        } catch (error) {
            console.error('خطأ في إلغاء الحجز:', error);
            throw error;
        }
    }
}

// الاستخدام
const bookingManager = new BookingManager(syncManager);

// إنشاء حجز جديد
const newBooking = {
    guest_name: 'أحمد محمد',
    room_number: '101',
    checkin_date: '2024-01-15',
    nights: 3
};

const result = await bookingManager.createBooking(newBooking);
console.log('نتيجة الحجز:', result);
```

---

## 🚨 معالجة الأخطاء

### أنواع الأخطاء الشائعة

```javascript
// معالجة شاملة للأخطاء
syncManager.on('error', (error) => {
    switch (error.type) {
        case 'NETWORK_ERROR':
            console.log('خطأ في الشبكة - سيتم المحاولة مرة أخرى');
            break;
            
        case 'AUTH_ERROR':
            console.log('خطأ في المصادقة - يجب تسجيل الدخول مرة أخرى');
            redirectToLogin();
            break;
            
        case 'CONFLICT_ERROR':
            console.log('تعارض في البيانات - يتطلب تدخل المستخدم');
            showConflictResolutionDialog(error.conflict);
            break;
            
        case 'STORAGE_ERROR':
            console.log('خطأ في التخزين - مساحة غير كافية');
            showStorageWarning();
            break;
            
        default:
            console.error('خطأ غير معروف:', error);
    }
});
```

### إعادة المحاولة التلقائية

```javascript
// تكوين إعادة المحاولة
syncManager.setRetryPolicy({
    maxAttempts: 3,
    backoffMultiplier: 2,
    initialDelay: 1000,
    maxDelay: 30000,
    
    // شروط إعادة المحاولة
    shouldRetry: (error, attempt) => {
        // لا تعيد المحاولة للأخطاء الدائمة
        if (error.type === 'AUTH_ERROR') return false;
        
        // أعد المحاولة للأخطاء المؤقتة
        return attempt < 3 && error.type === 'NETWORK_ERROR';
    }
});
```

---

## 📈 تحسين الأداء

### نصائح للأداء الأمثل

```javascript
// 1. استخدام المزامنة الانتقائية
syncManager.setSyncFilter((table, operation, data) => {
    // لا تزامن البيانات المؤقتة
    if (table === 'temp_data') return false;
    
    // زامن فقط التحديثات المهمة
    if (operation === 'update' && !data.important) return false;
    
    return true;
});

// 2. ضغط البيانات الكبيرة
syncManager.setCompressionThreshold(1024); // 1KB

// 3. تجميع العمليات
syncManager.enableBatching({
    maxBatchSize: 100,
    maxWaitTime: 5000 // 5 ثوان
});

// 4. تحسين التخزين المؤقت
syncManager.setCacheStrategy({
    maxSize: 50 * 1024 * 1024, // 50MB
    ttl: 3600000, // ساعة واحدة
    evictionPolicy: 'lru' // Least Recently Used
});
```

---

## 🔍 استكشاف الأخطاء

### أدوات التشخيص

```javascript
// تفعيل وضع التشخيص
syncManager.enableDiagnostics(true);

// تصدير تقرير التشخيص
const diagnostics = await syncManager.getDiagnostics();
console.log('تقرير التشخيص:', diagnostics);

// فحص سلامة البيانات
const integrityCheck = await syncManager.checkDataIntegrity();
if (!integrityCheck.valid) {
    console.warn('مشاكل في سلامة البيانات:', integrityCheck.issues);
}

// إعادة تعيين المزامنة (استخدم بحذر)
await syncManager.resetSync();
```

---

## 📚 المراجع والموارد

### روابط مفيدة
- [Supabase Realtime Documentation](https://supabase.com/docs/guides/realtime)
- [Service Worker API](https://developer.mozilla.org/en-US/docs/Web/API/Service_Worker_API)
- [IndexedDB Guide](https://developer.mozilla.org/en-US/docs/Web/API/IndexedDB_API)

### أمثلة إضافية
- [GitHub Repository](https://github.com/your-repo/hotel-management)
- [Demo Application](https://demo.hotel-management.com)
- [API Playground](https://api.hotel-management.com/playground)

---

*هذه الوثائق محدثة باستمرار. للحصول على أحدث المعلومات، يرجى مراجعة المستودع الرسمي.*