import 'package:flutter/material.dart';
import '../../services/mongodb_sync_service.dart';
import '../../models/guest_sync_model.dart';
import '../../utils/theme.dart';

class GuestsRealtimeScreen extends StatefulWidget {
  const GuestsRealtimeScreen({super.key});

  @override
  State<GuestsRealtimeScreen> createState() => _GuestsRealtimeScreenState();
}

class _GuestsRealtimeScreenState extends State<GuestsRealtimeScreen> {
  final _mongoService = MongoDBSyncService.instance;
  final _passwordController = TextEditingController();
  bool _isConnected = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _connectToMongo() async {
    if (_passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إدخال كلمة المرور')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _mongoService.initialize(_passwordController.text);
      setState(() {
        _isConnected = true;
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم الاتصال بنجاح')),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ في الاتصال: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('النزلاء - المزامنة الفورية'),
        backgroundColor: AppColors.primary,
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _mongoService.getAllGuests();
              },
            ),
        ],
      ),
      body: _isConnected ? _buildGuestsList() : _buildConnectionForm(),
    );
  }

  Widget _buildConnectionForm() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cloud_sync,
            size: 80,
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          const Text(
            'المزامنة الفورية مع MongoDB',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'اتصل بـ MongoDB لرؤية جميع النزلاء\nمن جميع الأجهزة في الوقت الفعلي',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _passwordController,
            obscureText: true,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              labelText: 'كلمة مرور MongoDB',
              hintText: 'أدخل كلمة المرور',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.lock),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _connectToMongo,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'اتصل الآن',
                    style: TextStyle(fontSize: 18, color: Colors.white),
                  ),
          ),
          const SizedBox(height: 16),
          const Text(
            '🔒 مجاني 100٪ - حتى 512 ميجابايت',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.green,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestsList() {
    return StreamBuilder<List<GuestSync>>(
      stream: _mongoService.guestsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text('خطأ: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _isConnected = false);
                  },
                  child: const Text('إعادة الاتصال'),
                ),
              ],
            ),
          );
        }

        final guests = snapshot.data ?? [];

        if (guests.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.people_outline, size: 80, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  'لا توجد نزلاء حالياً',
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                const Text(
                  'سيظهر النزلاء تلقائياً عند إضافتهم من أي جهاز',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.green.shade50,
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'متصل - يتم التحديث كل 5 ثواني\nعدد النزلاء: ${guests.length}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await _mongoService.getAllGuests();
                },
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: guests.length,
                  itemBuilder: (context, index) {
                    final guest = guests[index];
                    return _buildGuestCard(guest);
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuestCard(GuestSync guest) {
    final isFromThisDevice = guest.deviceId == _mongoService._deviceId;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFromThisDevice ? Colors.blue : Colors.grey.shade300,
          width: isFromThisDevice ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Text(
                    guest.fullName.isNotEmpty
                        ? guest.fullName[0].toUpperCase()
                        : '؟',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        guest.fullName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            guest.phone,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (isFromThisDevice)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'هذا الجهاز',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
              ],
            ),
            if (guest.email != null || guest.idNumber != null) ...[
              const Divider(height: 24),
              if (guest.email != null) ...[
                Row(
                  children: [
                    const Icon(Icons.email, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(guest.email!),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (guest.idNumber != null)
                Row(
                  children: [
                    const Icon(Icons.badge, size: 16, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text('رقم الهوية: ${guest.idNumber}'),
                  ],
                ),
            ],
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'آخر تحديث: ${_formatTime(guest.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                Icon(
                  Icons.sync,
                  size: 16,
                  color: Colors.green.shade400,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) {
      return 'منذ ${diff.inSeconds} ثانية';
    } else if (diff.inMinutes < 60) {
      return 'منذ ${diff.inMinutes} دقيقة';
    } else if (diff.inHours < 24) {
      return 'منذ ${diff.inHours} ساعة';
    } else {
      return 'منذ ${diff.inDays} يوم';
    }
  }
}
