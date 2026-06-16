import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

import '../../providers/repository_providers.dart';

class ServerIdFixerScreen extends ConsumerStatefulWidget {
  const ServerIdFixerScreen({super.key});

  @override
  ConsumerState<ServerIdFixerScreen> createState() =>
      _ServerIdFixerScreenState();
}

class _ServerIdFixerScreenState extends ConsumerState<ServerIdFixerScreen> {
  bool _isProcessing = false;
  String _status = '';
  int _updatedCount = 0;
  final List<String> _logs = [];

  final Map<String, String> _roomsMapping = {
    '82f73ed9-7c51-4696-93a8-c3fa753725f7':
        '82f73ed9-7c51-4696-93a8-c3fa753725f7',
    '6f10eef5-f834-4415-9db3-2d9d6791ce14':
        '6f10eef5-f834-4415-9db3-2d9d6791ce14',
    'fedc0bce-4b4f-48b2-87d2-e5a9a3a12168':
        'fedc0bce-4b4f-48b2-87d2-e5a9a3a12168',
    '23294cb8-f317-42c5-ab80-b3adc4c89b25':
        '23294cb8-f317-42c5-ab80-b3adc4c89b25',
    'e4d01db4-b6fd-4e6d-bcdc-80b5377a4a9b':
        'e4d01db4-b6fd-4e6d-bcdc-80b5377a4a9b',
    '1bb8f3de-a3e7-4b2b-baa3-ebea289dda8f':
        '1bb8f3de-a3e7-4b2b-baa3-ebea289dda8f',
    'cc95aada-bd9f-4dc8-a3ed-a63b66c06d96':
        'cc95aada-bd9f-4dc8-a3ed-a63b66c06d96',
    'ad485411-9a2e-4aa0-b571-a245e9932ef3':
        'ad485411-9a2e-4aa0-b571-a245e9932ef3',
    '6e723b44-79d9-4bff-b9c4-e4a72996a9c6':
        '6e723b44-79d9-4bff-b9c4-e4a72996a9c6',
    '598fbc3f-4ca4-4818-9c0f-303c00c83750':
        '598fbc3f-4ca4-4818-9c0f-303c00c83750',
    'cf47209b-7220-49f0-b8a3-b159e25db887':
        'cf47209b-7220-49f0-b8a3-b159e25db887',
    '5d2beb07-5253-46b3-a407-e74dc0eec880':
        '5d2beb07-5253-46b3-a407-e74dc0eec880',
    '7ebe6dd7-0644-4e3a-bc79-cd081f1757a6':
        '7ebe6dd7-0644-4e3a-bc79-cd081f1757a6',
    'ce686a8e-7e9b-452a-9908-7dbc8235b748':
        'ce686a8e-7e9b-452a-9908-7dbc8235b748',
    'c46defab-a53d-4366-832d-d85ced1f22fb':
        'c46defab-a53d-4366-832d-d85ced1f22fb',
    '9b7f6abb-af0c-4a92-a7f1-9d8ebadfc956':
        '9b7f6abb-af0c-4a92-a7f1-9d8ebadfc956',
    '7a82b56a-57a7-4032-8f8b-87a67f8f2186':
        '7a82b56a-57a7-4032-8f8b-87a67f8f2186',
    '20acc60c-4d0b-4728-b010-9e8328c39587':
        '20acc60c-4d0b-4728-b010-9e8328c39587',
    'a68ffc2a-c9d8-4ecd-87ec-65ddc8acd8f1':
        'a68ffc2a-c9d8-4ecd-87ec-65ddc8acd8f1',
  };

  Future<void> _fixServerIds() async {
    setState(() {
      _isProcessing = true;
      _status = 'بدء التحديث...';
      _updatedCount = 0;
      _logs.clear();
    });

    try {
      final db = ref.read(databaseProvider);

      _addLog('📊 بدء تحديث ${_roomsMapping.length} غرفة...');
      _addLog('🔍 التحقق من بنية قاعدة البيانات...');

      // التحقق من وجود عمود serverId
      try {
        await db.customStatement('SELECT server_id FROM rooms LIMIT 1');
        _addLog('✅ عمود serverId موجود في الجدول');
      } catch (e) {
        _addLog('❌ عمود serverId غير موجود!');
        _addLog('💡 يرجى إعادة تثبيت التطبيق أو الانتظار للتحديث التلقائي');

        setState(() {
          _status = 'فشل';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ خطأ: عمود serverId غير موجود في قاعدة البيانات'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      for (final entry in _roomsMapping.entries) {
        final localUuid = entry.key;
        final serverId = entry.value;

        try {
          await db.customStatement(
            'UPDATE rooms SET server_id = ? WHERE local_uuid = ?',
            [serverId, localUuid],
          );

          _updatedCount++;
          _addLog('✅ تم تحديث: $localUuid');
        } catch (e) {
          _addLog('❌ خطأ في $localUuid: $e');
        }
      }

      _addLog('\n✅ اكتمل التحديث!');
      _addLog('📊 تم تحديث $_updatedCount من ${_roomsMapping.length} غرفة');

      setState(() {
        _status = 'اكتمل بنجاح';
      });

      ref.invalidate(roomsListProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ تم تحديث $_updatedCount غرفة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      _addLog('❌ خطأ عام: $e');
      setState(() {
        _status = 'فشل';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.add(message);
      });
    }
    AppLogger.info(
  message,
);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إصلاح Server IDs للغرف'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue),
                        SizedBox(width: 8),
                        Text(
                          'حول هذه الأداة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'هذه الأداة تقوم بتحديث serverId لجميع الغرف في قاعدة البيانات المحلية لربطها مع Appwrite.',
                      style: TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'عدد الغرف المطلوب تحديثها: ${_roomsMapping.length}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _fixServerIds,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.build),
              label: Text(_isProcessing ? 'جاري التحديث...' : 'بدء الإصلاح'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                color: _status == 'اكتمل بنجاح'
                    ? Colors.green.shade50
                    : _status == 'فشل'
                    ? Colors.red.shade50
                    : Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _status == 'اكتمل بنجاح'
                            ? Icons.check_circle
                            : _status == 'فشل'
                            ? Icons.error
                            : Icons.pending,
                        color: _status == 'اكتمل بنجاح'
                            ? Colors.green
                            : _status == 'فشل'
                            ? Colors.red
                            : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'الحالة: $_status',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_updatedCount > 0) ...[
                        const Spacer(),
                        Text('$_updatedCount/${_roomsMapping.length}'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'سجل التنفيذ:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: _logs.isEmpty
                    ? const Center(
                        child: Text(
                          'لم يتم البدء بعد',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _logs.length,
                        itemBuilder: (context, index) {
                          final log = _logs[index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              log,
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
